import Foundation
import Observation
import SwiftUI

/// Everything the menu shows and every action it can take.
///
/// One polling loop drives the whole queue. It runs fast while the panel is
/// open and backs off while it is closed, and again when the rate-limit budget
/// runs low. Quiet repositories answer from the ETag cache, so the cadence
/// costs almost nothing when nothing is waiting.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case needsToken
        case connecting
        case ready
        case failed(String)
    }

    // Queue contents
    private(set) var approvals: [PendingApproval] = []
    private(set) var pullRequests: [PullRequestSummary] = []
    private(set) var failures: [FailedRun] = []
    private(set) var repos: [RepoRef] = []

    // Presentation state
    private(set) var phase: Phase = .needsToken
    private(set) var login: String?
    private(set) var rateLimit: RateLimit?
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var busyItems: Set<String> = []
    /// Why the last poll came back short. Shown in the footer rather than as a
    /// banner: a laptop that is offline for an hour should not stack up alerts.
    private(set) var pollProblem: String?
    /// Why the connect screen is showing again, when it is not a first run.
    private(set) var connectNotice: String?
    /// Set when the token can read but GitHub reports it cannot write.
    private(set) var scopeWarning: String?
    var banner: Banner?
    private(set) var menuIsOpen = false

    struct Banner: Identifiable, Equatable {
        enum Kind { case success, failure }
        let id = UUID()
        let kind: Kind
        let text: String
        /// Where the result of the action can be seen, when there is somewhere.
        var link: URL?
    }

    private let client: GitHubClient
    private let settings: Settings
    private let vault: TokenVault
    private var pollTask: Task<Void, Never>?
    private var hasStarted = false
    private var lastDiscovery: Date?
    /// Repositories that answered 403 or 404 for Actions. Skipped until the
    /// next discovery so a repo Cleared cannot read is not asked every poll.
    private var unreadable: Set<String> = []
    /// Set by the preview harness so seeded state is never overwritten by a
    /// live refresh (which, with no token, would blank the rate limit).
    private var isPreview = false

    /// New repositories are picked up without a restart.
    private static let discoveryInterval: TimeInterval = 3_600
    /// GitHub refuses to re-run anything older than this, so there is no point
    /// offering the button.
    private static let rerunWindow: TimeInterval = 30 * 86_400

    init(client: GitHubClient = GitHubClient(), settings: Settings = .shared, vault: TokenVault = .keychain) {
        self.client = client
        self.settings = settings
        self.vault = vault
    }

    // MARK: - Derived

    /// Pull requests that nothing is blocking — checks green, no conflicts, not a draft.
    var readyToMerge: [PullRequestSummary] {
        pullRequests.filter(\.isReadyToMerge).sorted { $0.updatedAt > $1.updatedAt }
    }

    var blockedPullRequests: [PullRequestSummary] {
        pullRequests.filter { !$0.isReadyToMerge }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// What the menu bar shows. Held deployments outrank everything else.
    var pendingCount: Int { approvals.count + readyToMerge.count }

    var isAllClear: Bool { pendingCount == 0 }

    // MARK: - Lifecycle

    /// Called once, when the app launches.
    func start() async {
        guard !hasStarted, !isPreview else { return }
        hasStarted = true
        Log.app.notice("starting\(AppEnvironment.isSandboxed ? " (sandboxed)" : "", privacy: .public)")
        guard vault.current() != nil else {
            phase = .needsToken
            return
        }
        await connect()
    }

    func connect() async {
        phase = .connecting
        do {
            let viewer = try await client.viewer()
            login = viewer.login
            scopeWarning = viewer.canWrite
                ? nil
                : "This token is missing the repo scope, so clearing, merging and re-running will be refused."
            try await discoverRepos()
            connectNotice = nil
            phase = .ready
            Log.app.notice("connected; watching \(self.repos.count) repositories")
            startPolling()
            // Not awaited: the first run shows a system prompt, and the queue
            // should not wait on it.
            Task { await Notifier.shared.requestAuthorizationIfNeeded() }
            await refresh()
        } catch let error as GitHubError where error.isUnauthorized {
            tokenRejected()
        } catch {
            Log.app.error("connect failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    func signIn(token: String) async {
        do {
            try vault.save(token)
            await client.clearCache()
            await connect()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func signInFromGHCLI() async {
        do {
            let token = try await GHCLIImporter.importToken()
            await signIn(token: token)
        } catch {
            banner = Banner(kind: .failure, text: error.localizedDescription)
        }
    }

    func signOut() {
        vault.clear()
        resetSession()
        connectNotice = nil
        phase = .needsToken
        Task { await client.clearCache() }
        Log.app.notice("signed out")
    }

    /// GitHub answered 401: the token was revoked or has expired. Polling on
    /// would only repeat the failure, so go back to the connect screen and say why.
    private func tokenRejected() {
        Log.app.notice("token rejected by GitHub")
        resetSession()
        connectNotice = "GitHub rejected the saved token — it was revoked or has expired. Connect again to carry on."
        phase = .needsToken
    }

    private func resetSession() {
        pollTask?.cancel()
        pollTask = nil
        approvals = []
        pullRequests = []
        failures = []
        repos = []
        unreadable = []
        login = nil
        rateLimit = nil
        lastRefresh = nil
        lastDiscovery = nil
        pollProblem = nil
        scopeWarning = nil
        Notifier.shared.reset()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.pollDelay else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// The panel came on screen. Always refreshes, even if it was already
    /// thought to be open: showing a stale queue is the worse mistake.
    func panelDidOpen() {
        let wasOpen = menuIsOpen
        menuIsOpen = true
        guard case .ready = phase, !isPreview else { return }
        if !wasOpen {
            Log.app.debug("panel opened")
            // Restart the loop so the faster cadence applies now, not after
            // the long background sleep already in progress.
            startPolling()
        }
        Task { await refresh() }
    }

    func panelDidClose() {
        guard menuIsOpen else { return }
        menuIsOpen = false
        guard case .ready = phase, !isPreview else { return }
        Log.app.debug("panel closed")
        startPolling()
    }

    /// Seconds until the next poll: the configured interval, slowed while
    /// nobody is looking, and slowed again when the budget is nearly spent.
    var pollDelay: TimeInterval {
        let background = menuIsOpen ? 1 : settings.backgroundMultiplier
        let scarcity = (rateLimit?.isLow ?? false) ? 4 : 1
        return settings.approvalInterval * Double(background * scarcity)
    }

    // MARK: - Refresh

    func discoverRepos() async throws {
        let discovered = try await client.discoverRepos(
            activeWithinDays: settings.discoveryDays,
            limit: settings.repoLimit
        )
        let excluded = settings.excludedRepos
        let pinned = settings.pinnedRepos.compactMap(RepoRef.init(fullName:))
        var merged = pinned
        for repo in discovered where !merged.contains(repo) {
            merged.append(repo)
        }
        repos = merged.filter { !excluded.contains($0.id) }
        unreadable = []
        lastDiscovery = Date()
    }

    /// Re-reads the repository list after a setting that shapes it changes.
    func rediscover() async {
        guard case .ready = phase, !isPreview else { return }
        do {
            try await discoverRepos()
            await refresh()
        } catch {
            banner = Banner(kind: .failure, text: error.localizedDescription)
        }
    }

    func refresh() async {
        guard !isPreview else { return }
        guard case .ready = phase, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if let lastDiscovery, Date().timeIntervalSince(lastDiscovery) > Self.discoveryInterval {
            // Best effort: a failed rediscovery keeps the list it already has.
            try? await discoverRepos()
        }

        async let approvalResult = fetchApprovals()
        async let pullRequestResult = fetchPullRequests()
        async let failureResult = fetchFailures()
        let (newApprovals, newPRs, newFailures) = await (approvalResult, pullRequestResult, failureResult)

        let problems = [newApprovals.problem, newPRs.problem, newFailures.problem].compactMap { $0 }
        if problems.contains(where: { ($0 as? GitHubError)?.isUnauthorized == true }) {
            tokenRejected()
            return
        }
        // Signing out mid-poll must not repopulate the queue it just emptied.
        guard case .ready = phase else { return }

        if let items = newApprovals.items { approvals = items.sorted { $0.waitingSince < $1.waitingSince } }
        if let items = newPRs.items { pullRequests = items }
        if let items = newFailures.items { failures = items }

        pollProblem = problems.first?.localizedDescription
        rateLimit = await client.currentRateLimit()
        lastRefresh = Date()
        Log.poll.debug("poll: \(self.approvals.count) holding, \(self.readyToMerge.count) ready, \(self.failures.count) failed, problem: \(self.pollProblem ?? "none", privacy: .public)")

        Notifier.shared.announceHolds(approvals)
        Notifier.shared.announceFailures(failures)
    }

    /// What one lane of a poll produced. `items` is nil when the lane failed
    /// outright and the previous contents should stay on screen.
    private struct Fetched<Item: Sendable>: Sendable {
        var items: [Item]?
        var problem: (any Error)?
    }

    /// True for a failure that will repeat for every repository, so there is
    /// no point asking the rest: no network, no budget, or no valid token.
    private func endsPoll(_ error: any Error) -> Bool {
        switch error as? GitHubError {
        case .transport, .rateLimited, .notAuthenticated: true
        case .http(let status, _): status == 401
        case .decoding, nil: false
        }
    }

    private func isUnreadable(_ error: any Error) -> Bool {
        if case .http(let status, _)? = error as? GitHubError { return status == 403 || status == 404 }
        return false
    }

    private func fetchApprovals() async -> Fetched<PendingApproval> {
        var collected: [PendingApproval] = []
        var problem: (any Error)?
        // Sequential on purpose: quiet repositories answer 304 in single-digit
        // milliseconds, and a burst of parallel writes to the ETag cache buys
        // nothing but a thundering herd against secondary rate limits.
        for repo in repos where !unreadable.contains(repo.id) {
            do {
                collected.append(contentsOf: try await client.pendingApprovals(in: repo))
            } catch {
                if isUnreadable(error) {
                    // Actions is off, or the token cannot see it. Not an error
                    // worth showing; just stop asking.
                    unreadable.insert(repo.id)
                    continue
                }
                problem = error
                if endsPoll(error) { return Fetched(items: nil, problem: error) }
            }
        }
        return Fetched(items: collected, problem: problem)
    }

    private func fetchPullRequests() async -> Fetched<PullRequestSummary> {
        do {
            return Fetched(items: try await client.myOpenPullRequests())
        } catch {
            return Fetched(items: nil, problem: error)
        }
    }

    private func fetchFailures() async -> Fetched<FailedRun> {
        guard settings.showFailures else { return Fetched(items: []) }
        let cutoff = Date().addingTimeInterval(-Self.rerunWindow)
        var collected: [FailedRun] = []
        for repo in repos.prefix(6) where !unreadable.contains(repo.id) {
            do {
                collected.append(contentsOf: try await client.recentFailures(in: repo, limit: 3))
            } catch {
                // The approvals lane reports problems; this one only needs to
                // know when to stop.
                if endsPoll(error) { return Fetched(items: nil) }
            }
        }
        let recent = collected
            .filter { $0.finishedAt >= cutoff }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(5)
        return Fetched(items: Array(recent))
    }

    // MARK: - Actions

    func clear(_ approval: PendingApproval) async {
        await perform(id: approval.id, success: "Cleared · \(approval.runName)") {
            try await self.client.approve(approval)
            self.approvals.removeAll { $0.id == approval.id }
            return nil
        }
    }

    func reject(_ approval: PendingApproval, comment: String) async {
        let reason = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform(id: approval.id, success: "Rejected · \(approval.runName)") {
            try await self.client.reject(approval, comment: reason.isEmpty ? "Rejected from the menu bar" : reason)
            self.approvals.removeAll { $0.id == approval.id }
            return nil
        }
    }

    func merge(_ pr: PullRequestSummary) async {
        let method = pr.mergeMethod(preferring: settings.mergeMethod)
        await perform(id: pr.id, success: "Merged · \(pr.repo.name) #\(pr.number)") {
            try await self.client.merge(pr, method: method)
            self.pullRequests.removeAll { $0.id == pr.id }
            return nil
        }
    }

    func rerun(_ run: FailedRun) async {
        await perform(id: run.id, success: "Re-running · \(run.name)") {
            try await self.client.rerunFailedJobs(run)
            self.failures.removeAll { $0.id == run.id }
            return nil
        }
    }

    /// The Clear button on a notification. The hold is looked up fresh: by the
    /// time someone clicks, it may already have been cleared elsewhere.
    func clearHold(withID id: String) async {
        guard let approval = approvals.first(where: { $0.id == id }) else {
            banner = Banner(kind: .failure, text: "That deployment is no longer waiting.")
            return
        }
        await clear(approval)
    }

    func rerunFailure(withID id: String) async {
        guard let run = failures.first(where: { $0.id == id }) else {
            banner = Banner(kind: .failure, text: "That run is no longer listed as failed.")
            return
        }
        await rerun(run)
    }

    func workflowCatalog(for repo: RepoRef) async throws -> WorkflowCatalog {
#if DEBUG
        if isPreview { return SampleData.catalog }
#endif
        return try await client.workflowCatalog(in: repo)
    }

    func dispatch(_ workflow: DispatchableWorkflow, ref: String, inputs: [String: String]) async {
        await perform(id: workflow.id, success: "Started · \(workflow.name)") {
            try await self.client.dispatch(workflow, ref: ref, inputs: inputs)
        }
    }

    /// Runs one action, shows what happened, and re-reads the queue. `work`
    /// returns a link to the result when GitHub hands one back.
    private func perform(id: String, success: String, _ work: @escaping () async throws -> URL?) async {
        // The preview has no GitHub behind it; its buttons are for looking at.
        guard !isPreview, !busyItems.contains(id) else { return }
        busyItems.insert(id)
        defer { busyItems.remove(id) }
        do {
            let link = try await work()
            banner = Banner(kind: .success, text: success, link: link)
            // Re-read soon: clearing a gate usually starts a run worth showing.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await self?.refresh()
            }
        } catch {
            Log.app.error("action failed: \(error.localizedDescription, privacy: .public)")
            banner = Banner(kind: .failure, text: error.localizedDescription)
        }
    }

    func isBusy(_ id: String) -> Bool { busyItems.contains(id) }

#if DEBUG
    /// Seeds the model from fixtures and parks it in `.ready` without touching
    /// the network. Used by SwiftUI previews and the `--ui-preview` harness.
    func loadSample(empty: Bool = false, overflow: Bool = false) {
        isPreview = true
        pollTask?.cancel()
        pollTask = nil
        login = "octocat"
        repos = SampleData.repos
        approvals = empty ? [] : SampleData.approvals.sorted { $0.waitingSince < $1.waitingSince }
        pullRequests = empty ? [] : (overflow ? SampleData.manyPullRequests : SampleData.pullRequests)
        failures = empty ? [] : SampleData.failures
        rateLimit = RateLimit(remaining: 4_812, limit: 5_000, resetsAt: Date().addingTimeInterval(2_400))
        lastRefresh = Date()
        phase = .ready
    }

    /// Parks the model on the connect screen, for laying that screen out.
    func loadConnectScreen() {
        isPreview = true
        pollTask?.cancel()
        pollTask = nil
        login = nil
        phase = .needsToken
    }
#endif
}
