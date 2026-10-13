import Testing
import Foundation
@testable import Cleared

@Suite("RepoRef")
struct RepoRefTests {
    @Test("parses owner/name")
    func parsesFullName() {
        let repo = RepoRef(fullName: "hollandcloud/cleared")
        #expect(repo?.owner == "hollandcloud")
        #expect(repo?.name == "cleared")
        #expect(repo?.id == "hollandcloud/cleared")
    }

    @Test("rejects malformed names", arguments: ["", "nope", "a/b/c", "/", "owner/"])
    func rejectsMalformed(_ input: String) {
        #expect(RepoRef(fullName: input) == nil)
    }
}

@Suite("Merge readiness")
struct MergeReadinessTests {
    private func pr(
        checks: CheckState = .success,
        mergeable: String = "mergeable",
        draft: Bool = false,
        state: MergeState = .clean,
        review: ReviewDecision? = nil,
        queued: Bool = false,
        allowed: [MergeMethod] = [],
        repoDefault: MergeMethod? = nil
    ) -> PullRequestSummary {
        PullRequestSummary(
            repo: RepoRef(owner: "o", name: "r"),
            number: 1,
            title: "feat: thing",
            branch: "feat/thing",
            isDraft: draft,
            checkState: checks,
            mergeable: mergeable,
            htmlURL: URL(string: "https://github.com/o/r/pull/1")!,
            updatedAt: Date(),
            mergeState: state,
            reviewDecision: review,
            isInMergeQueue: queued,
            allowedMethods: allowed,
            repoDefaultMethod: repoDefault
        )
    }

    @Test("green, mergeable, not a draft is ready")
    func greenIsReady() {
        #expect(pr().isReadyToMerge)
        #expect(pr().blockReason == nil)
    }

    @Test("a draft is never ready")
    func draftBlocked() {
        let draft = pr(draft: true)
        #expect(!draft.isReadyToMerge)
        #expect(draft.blockReason == "draft")
    }

    @Test("conflicts block the merge button")
    func conflictsBlocked() {
        let conflicting = pr(mergeable: "conflicting")
        #expect(!conflicting.isReadyToMerge)
        #expect(conflicting.blockReason == "conflicts")
    }

    @Test("checks that are not green block the merge button", arguments: [
        (CheckState.pending, "checks running"),
        (CheckState.failure, "checks failed"),
        (CheckState.none, "no checks"),
    ])
    func checksBlock(state: CheckState, reason: String) {
        let blocked = pr(checks: state)
        #expect(!blocked.isReadyToMerge)
        #expect(blocked.blockReason == reason)
    }

    @Test("green checks are not enough when GitHub's own rules still block the merge", arguments: [
        (MergeState.blocked, ReviewDecision.reviewRequired as ReviewDecision?, "needs review"),
        (MergeState.blocked, ReviewDecision.changesRequested, "changes requested"),
        (MergeState.blocked, ReviewDecision.approved, "blocked by branch rules"),
        (MergeState.blocked, nil, "blocked by branch rules"),
        (MergeState.behind, nil, "behind base branch"),
        (MergeState.dirty, nil, "conflicts"),
        (MergeState.unknown, nil, "GitHub is still checking"),
    ])
    func branchRulesBlock(state: MergeState, review: ReviewDecision?, reason: String) {
        let blocked = pr(state: state, review: review)
        #expect(!blocked.isReadyToMerge)
        #expect(blocked.blockReason == reason)
    }

    @Test("an approved pull request in a clean state is ready", arguments: [MergeState.clean, .hasHooks, .unstable])
    func approvedIsReady(state: MergeState) {
        #expect(pr(state: state, review: .approved).isReadyToMerge)
    }

    @Test("a pull request already in the merge queue has no merge button")
    func queuedIsNotOffered() {
        #expect(pr(queued: true).blockReason == "in merge queue")
    }

    @Test("mergeability GitHub has not computed yet is not treated as mergeable")
    func unknownMergeability() {
        let pending = pr(mergeable: "unknown")
        #expect(!pending.isReadyToMerge)
        #expect(pending.blockReason == "GitHub is still checking")
    }

    @Test("the preferred merge method is used wherever the repository allows it")
    func prefersConfiguredMethod() {
        #expect(pr(allowed: [.squash, .merge, .rebase]).mergeMethod(preferring: .rebase) == .rebase)
        // Nothing known about the repository: trust the preference.
        #expect(pr().mergeMethod(preferring: .merge) == .merge)
    }

    @Test("a repository that forbids the preferred method gets its own default instead")
    func fallsBackToRepoDefault() {
        #expect(pr(allowed: [.merge, .rebase], repoDefault: .rebase).mergeMethod(preferring: .squash) == .rebase)
        #expect(pr(allowed: [.merge], repoDefault: .squash).mergeMethod(preferring: .rebase) == .merge)
    }
}

@Suite("Pending approval")
struct PendingApprovalTests {
    private func approval(environments: [PendingApproval.Environment]) -> PendingApproval {
        PendingApproval(
            repo: RepoRef(owner: "o", name: "r"),
            runID: 42,
            runName: "Deploy Production",
            branch: "main",
            environments: environments,
            waitingSince: Date().addingTimeInterval(-3600),
            htmlURL: URL(string: "https://github.com/o/r/actions/runs/42")!
        )
    }

    @Test("collapses multiple environments for display and for the approve call")
    func multipleEnvironments() {
        let item = approval(environments: [.init(id: 1, name: "production"), .init(id: 2, name: "prod-eu")])
        #expect(item.environmentNames == "production, prod-eu")
        #expect(item.environmentIDs == [1, 2])
        #expect(item.id == "o/r#42")
    }

    @Test("the same run held at a different gate is a new thing to announce")
    func announcementKeyTracksTheGate() {
        let staging = approval(environments: [.init(id: 1, name: "staging")])
        let production = approval(environments: [.init(id: 2, name: "production")])
        #expect(staging.id == production.id)
        #expect(staging.announcementKey != production.announcementKey)
        #expect(staging.announcementKey == approval(environments: [.init(id: 1, name: "renamed")]).announcementKey)
    }
}

@Suite("Announcements")
struct AnnouncementLedgerTests {
    @Test("a hold already waiting at launch is announced; an old failure is not")
    func firstSight() {
        var holds = AnnouncementLedger()
        var failures = AnnouncementLedger()
        #expect(holds.fresh(in: ["a", "b"], announceFirstSight: true) == ["a", "b"])
        #expect(failures.fresh(in: ["a", "b"], announceFirstSight: false).isEmpty)
    }

    @Test("each item is announced once, however many polls see it")
    func announcesOnce() {
        var ledger = AnnouncementLedger()
        _ = ledger.fresh(in: ["a"], announceFirstSight: true)
        #expect(ledger.fresh(in: ["a"], announceFirstSight: true).isEmpty)
        #expect(ledger.fresh(in: ["a", "b"], announceFirstSight: true) == ["b"])
    }

    @Test("something that leaves and comes back is announced again")
    func reannouncesAfterLeaving() {
        var ledger = AnnouncementLedger()
        _ = ledger.fresh(in: ["a"], announceFirstSight: true)
        _ = ledger.fresh(in: [], announceFirstSight: true)
        #expect(ledger.fresh(in: ["a"], announceFirstSight: true) == ["a"])
    }

    @Test("reports what has gone, so its notification can be withdrawn")
    func reportsDepartures() {
        var ledger = AnnouncementLedger()
        #expect(ledger.departed(from: ["a"]).isEmpty)
        _ = ledger.fresh(in: ["a", "b"], announceFirstSight: true)
        #expect(ledger.departed(from: ["b"]) == ["a"])
    }
}

@MainActor
@Suite("Settings")
struct SettingsTests {
    private let scratch = ScratchSettings()
    private var settings: Settings { scratch.settings }

    @Test("ships with one-click actions and squash merges")
    func defaults() {
        #expect(settings.approvalInterval == 30)
        #expect(settings.backgroundMultiplier == 4)
        #expect(settings.mergeMethod == .squash)
        #expect(settings.confirmActions == false)
        #expect(settings.notifyOnHold)
        #expect(settings.notifyOnFailure == false)
    }

    @Test("the poll interval is kept inside sane bounds")
    func clampsInterval() {
        settings.approvalInterval = 1
        #expect(settings.approvalInterval == 10)
        settings.approvalInterval = 9_000
        #expect(settings.approvalInterval == 300)
    }

    @Test("the merge method survives a round trip")
    func storesMergeMethod() {
        settings.mergeMethod = .rebase
        #expect(settings.mergeMethod == .rebase)
    }

    @Test("an ignored repository can be watched again")
    func ignoreIsReversible() {
        settings.setExcluded(true, "acme/web")
        #expect(settings.excludedRepos == ["acme/web"])
        settings.setExcluded(false, "acme/web")
        #expect(settings.excludedRepos.isEmpty)
    }

    @Test("pinning accepts owner/name, once, and un-ignores it")
    func pins() {
        settings.setExcluded(true, "acme/quiet")
        #expect(settings.pin("  acme/quiet\n"))
        #expect(settings.pin("ACME/Quiet"))
        #expect(settings.pinnedRepos == ["acme/quiet"])
        #expect(settings.excludedRepos.isEmpty)

        settings.unpin("acme/quiet")
        #expect(settings.pinnedRepos.isEmpty)
    }

    @Test("pinning rejects anything that is not owner/name", arguments: ["", "nope", "a/b/c", "https://github.com/acme/web"])
    func rejectsBadPins(input: String) {
        #expect(settings.pin(input) == false)
        #expect(settings.pinnedRepos.isEmpty)
    }
}

@Suite("Held duration")
struct HeldDurationTests {
    @Test("renders the unit that matters at each scale", arguments: [
        (30.0, "30s"), (600.0, "10m"), (7200.0, "2h"), (172_800.0, "2d"),
    ])
    func formats(seconds: Double, expected: String) {
        let past = Date().addingTimeInterval(-seconds)
        #expect(past.heldDuration == expected)
    }

    @Test("never renders a negative duration for a clock skew into the future")
    func futureIsZero() {
        #expect(Date().addingTimeInterval(120).heldDuration == "0s")
    }
}

@Suite("Token handling")
struct TokenTests {
    @Test("a fingerprint never reveals the middle of the token")
    func fingerprintRedacts() {
        let token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        let printed = TokenStore.fingerprint(token)
        #expect(printed.contains("ghp_"))
        #expect(printed.contains("2345"))
        #expect(!printed.contains("MNOPQRST"))
    }

    @Test("an empty token is rejected rather than stored")
    func rejectsEmpty() {
        #expect(throws: TokenStore.TokenError.self) {
            try TokenStore.save("   \n ")
        }
    }
}

@Suite("Rate limit")
struct RateLimitTests {
    @Test("flags a low budget so polling can back off")
    func lowBudget() {
        let low = RateLimit(remaining: 120, limit: 5000, resetsAt: Date())
        let healthy = RateLimit(remaining: 4800, limit: 5000, resetsAt: Date())
        #expect(low.isLow)
        #expect(!healthy.isLow)
        #expect(healthy.fraction > 0.9)
    }
}

@Suite("Error messages")
struct ErrorMessageTests {
    @Test("a 403 about scopes tells you which scope")
    func scopeMessage() {
        let error = GitHubError.http(status: 403, message: "Resource not accessible")
        #expect(error.localizedDescription.contains("repo scope"))
    }

    @Test("a 403 from an SSO-protected organization says to authorize the token")
    func ssoMessage() {
        let error = GitHubError.http(status: 403, message: "Resource protected by organization SAML enforcement.")
        #expect(error.localizedDescription.contains("single sign-on"))
    }

    @Test("a rate limit says how long until Cleared tries again")
    func rateLimitedMessage() {
        let error = GitHubError.rateLimited(until: Date().addingTimeInterval(11 * 60 + 30))
        #expect(error.localizedDescription.contains("12m"))
    }

    @Test("a 403 about rate limits says so instead")
    func rateMessage() {
        let error = GitHubError.http(status: 403, message: "API rate limit exceeded")
        #expect(error.localizedDescription.contains("Rate limited"))
    }

    @Test("a 401 tells you to reconnect")
    func unauthorizedMessage() {
        #expect(GitHubError.http(status: 401, message: "Bad credentials")
            .localizedDescription.contains("Reconnect"))
    }
}


#if DEBUG
@Suite("Preview harness arguments")
@MainActor
struct PreviewArgumentTests {
    typealias Fixture = PreviewHarness.Fixture

    @Test("selects a fixture by case name, not by display label", arguments: [
        ("full", Fixture.full), ("overflow", Fixture.overflow), ("empty", Fixture.empty),
    ])
    func selectsByKey(argument: String, expected: Fixture) {
        #expect(Fixture.fromCommandLine(["Cleared", "--ui-preview", argument]) == expected)
    }

    @Test("falls back to the full queue when the name is absent or unknown", arguments: [
        ["Cleared"],
        ["Cleared", "--ui-preview"],
        ["Cleared", "--ui-preview", "nonsense"],
        ["Cleared", "--ui-preview", "All clear"],
    ])
    func fallsBack(args: [String]) {
        #expect(Fixture.fromCommandLine(args) == .full)
    }
}
#endif
