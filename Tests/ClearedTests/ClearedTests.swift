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
        draft: Bool = false
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
            updatedAt: Date()
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
    @Test("a 403 about scopes tells you which scopes")
    func scopeMessage() {
        let error = GitHubError.http(status: 403, message: "Resource not accessible")
        #expect(error.localizedDescription.contains("repo and workflow"))
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
