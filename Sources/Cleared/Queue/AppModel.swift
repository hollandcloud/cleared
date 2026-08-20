import Foundation
import Observation
import SwiftUI

/// Everything the menu shows and every action it can take.
///
/// Two polling lanes run at different rates. The approval lane is fast because a
/// held deployment is the thing that costs real time; the merge lane is slower
/// because a pull request that just turned green will still be green in a
/// minute. Both back off when the menu is closed.
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
    private(set) var workflows: [DispatchableWorkflow] = []

    // Presentation state
    private(set) var phase: Phase = .needsToken
    private(set) var login: String?
    private(set) var rateLimit: RateLimit?
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private(set) var busyItems: Set<String> = []
    var banner: Banner?
    var menuIsOpen = false { didSet { if menuIsOpen { Task { await refresh() } } } }

    struct Banner: Identifiable, Equatable {
        enum Kind { case success, failure }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    private let client = GitHubClient()
    private var pollTask: Task<Void, Never>?
    private let settings = Settings.shared
    /// Set by the preview harness so seeded state is never overwritten by a
    /// live refresh (which, with no token, would blank the rate limit).
    private var isPreview = false

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

    func start() async {
        await Notifier.shared.requestAuthorizationIfNeeded()
        guard TokenStore.current() != nil else {
            phase = .needsToken
            return
        }
        phase = .connecting
        await connect()
        startPolling()
    }

    func connect() async {
        do {
            login = try await client.viewerLogin()
            try await discoverRepos()
            phase = .ready
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func signIn(token: String) async {
        do {
            try TokenStore.save(token)
            await client.clearCache()
            phase = .connecting
            await connect()
            startPolling()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func signInFromGHCLI() async {
        do {
            let token = try GHCLIImporter.importToken()
            await signIn(token: token)
        } catch {
            banner = Banner(kind: .failure, text: error.localizedDescription)
        }
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        TokenStore.clear()
        approvals = []
        pullRequests = []
        failures = []
        repos = []
        login = nil
        phase = .needsToken
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let base = await MainActor.run { self.settings.approvalInterval }
                let multiplier = await MainActor.run { self.menuIsOpen ? 1 : self.settings.backgroundMultiplier }
                let low = await MainActor.run { self.rateLimit?.isLow ?? false }
                let delay = base * Double(multiplier) * (low ? 4 : 1)

                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
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
    }

    func refresh() async {
        guard !isPreview else { return }
        guard case .ready = phase, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let approvalResult = fetchApprovals()
        async let pullRequestResult = fetchPullRequests()
        async let failureResult = fetchFailures()

        let (newApprovals, newPRs, newFailures) = await (approvalResult, pullRequestResult, failureResult)

        if let newApprovals { approvals = newApprovals.sorted { $0.waitingSince < $1.waitingSince } }
        if let newPRs { pullRequests = newPRs }
        if let newFailures { failures = newFailures }

        rateLimit = await client.currentRateLimit()
        lastRefresh = Date()
        await Notifier.shared.announceHolds(approvals)
    }

    private func fetchApprovals() async -> [PendingApproval]? {
        var collected: [PendingApproval] = []
        var sawError: String?
        // Sequential on purpose: quiet repositories answer 304 in single-digit
        // milliseconds, and a burst of parallel writes to the ETag cache buys
        // nothing but a thundering herd against secondary rate limits.
        for repo in repos {
            do {
                collected.append(contentsOf: try await client.pendingApprovals(in: repo))
            } catch let error as GitHubError {
                if case .http(let status, _) = error, status == 404 || status == 403 { continue }
                sawError = error.localizedDescription
            } catch {
                sawError = error.localizedDescription
            }
        }
        if let sawError, collected.isEmpty {
            banner = Banner(kind: .failure, text: sawError)
            return nil
        }
        return collected
    }

    private func fetchPullRequests() async -> [PullRequestSummary]? {
        do {
            return try await client.myOpenPullRequests()
        } catch {
            return nil
        }
    }

    private func fetchFailures() async -> [FailedRun]? {
        guard settings.showFailures else { return [] }
        var collected: [FailedRun] = []
        for repo in repos.prefix(6) {
            if let runs = try? await client.recentFailures(in: repo, limit: 3) {
                collected.append(contentsOf: runs)
            }
        }
        return collected
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Actions

    func clear(_ approval: PendingApproval) async {
        await perform(id: approval.id, success: "Cleared · \(approval.runName)") {
            try await self.client.approve(approval)
            self.approvals.removeAll { $0.id == approval.id }
        }
    }

    func merge(_ pr: PullRequestSummary) async {
        await perform(id: pr.id, success: "Merged · \(pr.repo.name) #\(pr.number)") {
            try await self.client.merge(pr, method: self.settings.mergeMethod)
            self.pullRequests.removeAll { $0.id == pr.id }
        }
    }

    func rerun(_ run: FailedRun) async {
        await perform(id: run.id, success: "Re-running · \(run.name)") {
            try await self.client.rerunFailedJobs(run)
            self.failures.removeAll { $0.id == run.id }
        }
    }

    func loadWorkflows(for repo: RepoRef) async {
        workflows = (try? await client.dispatchableWorkflows(in: repo)) ?? []
    }

    func dispatch(_ workflow: DispatchableWorkflow, ref: String, inputs: [String: String]) async {
        await perform(id: workflow.id, success: "Started · \(workflow.name)") {
            try await self.client.dispatch(workflow, ref: ref, inputs: inputs)
        }
    }

    private func perform(id: String, success: String, _ work: @escaping () async throws -> Void) async {
        busyItems.insert(id)
        defer { busyItems.remove(id) }
        do {
            try await work()
            banner = Banner(kind: .success, text: success)
            // Re-read soon: clearing a gate usually starts a run worth showing.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await self?.refresh()
            }
        } catch {
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
#endif
}
