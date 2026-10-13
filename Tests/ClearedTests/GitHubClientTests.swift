import Testing
import Foundation
@testable import Cleared

private let repo = RepoRef(owner: "acme", name: "web")

private func approval(run: Int = 42, environments: [Int] = [1, 2]) -> PendingApproval {
    PendingApproval(
        repo: repo,
        runID: run,
        runName: "Deploy",
        branch: "main",
        environments: environments.map { .init(id: $0, name: "env\($0)") },
        waitingSince: Date(),
        htmlURL: URL(string: "https://github.com/acme/web/actions/runs/\(run)")!
    )
}

private func pullRequest(headSHA: String = "abc123") -> PullRequestSummary {
    PullRequestSummary(
        repo: repo,
        number: 7,
        title: "feat: thing",
        branch: "feat/thing",
        isDraft: false,
        checkState: .success,
        mergeable: "mergeable",
        htmlURL: URL(string: "https://github.com/acme/web/pull/7")!,
        updatedAt: Date(),
        headSHA: headSHA
    )
}

@Suite("Conditional requests")
struct ConditionalRequestTests {
    @Test("a repeat poll sends the ETag and reuses the cached body on 304")
    func reusesCachedBody() async throws {
        let github = StubGitHub()
        github.respond { request in
            request.headers["If-None-Match"] == "\"v1\""
                ? .json("", status: 304)
                : .json(Fixture.runs([]), headers: ["ETag": "\"v1\""])
        }
        let client = github.client()

        let first = try await client.pendingApprovals(in: repo)
        let second = try await client.pendingApprovals(in: repo)

        #expect(first.isEmpty && second.isEmpty)
        #expect(github.requests.count == 2)
        #expect(github.requests[0].headers["If-None-Match"] == nil)
        #expect(github.requests[1].headers["If-None-Match"] == "\"v1\"")
    }

    @Test("a held run's pending deployments are revalidated, not re-downloaded")
    func cachesPendingDeployments() async throws {
        let github = StubGitHub()
        github.respond { request in
            if request.headers["If-None-Match"] != nil { return .json("", status: 304) }
            return request.path.contains("pending_deployments")
                ? .json(Fixture.pendingDeployments([(1, "production", true)]), headers: ["ETag": "\"d1\""])
                : .json(Fixture.runs([42]), headers: ["ETag": "\"r1\""])
        }
        let client = github.client()

        _ = try await client.pendingApprovals(in: repo)
        let again = try await client.pendingApprovals(in: repo)

        #expect(again.map(\.runID) == [42])
        #expect(github.requests.suffix(2).allSatisfy { $0.headers["If-None-Match"] != nil })
    }

    @Test("without a token nothing is sent")
    func refusesWithoutToken() async {
        let github = StubGitHub()
        let client = github.client(authenticated: false)

        await #expect(throws: GitHubError.notAuthenticated) {
            _ = try await client.viewer()
        }
        #expect(github.requests.isEmpty)
    }
}

@Suite("Rate limits")
struct RateLimitHandlingTests {
    private func limitHeaders(resource: String, remaining: Int, reset: Double = 1_800_003_600) -> [String: String] {
        [
            "X-RateLimit-Resource": resource,
            "X-RateLimit-Remaining": "\(remaining)",
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Reset": "\(Int(reset))",
        ]
    }

    @Test("the footer shows the REST budget even after a GraphQL call")
    func keepsBudgetsApart() async throws {
        let github = StubGitHub()
        github.respond { [self] request in
            request.path == "/graphql"
                ? .json(Fixture.search([]), headers: limitHeaders(resource: "graphql", remaining: 4_999))
                : .json(#"{"login": "octocat"}"#, headers: limitHeaders(resource: "core", remaining: 4_000))
        }
        let client = github.client()

        _ = try await client.viewer()
        _ = try await client.myOpenPullRequests()

        #expect(await client.currentRateLimit()?.remaining == 4_000)
    }

    @Test("a secondary limit pauses requests for as long as GitHub asked")
    func honoursRetryAfter() async throws {
        let github = StubGitHub()
        github.respond { _ in
            .json(#"{"message": "You have exceeded a secondary rate limit."}"#, status: 403, headers: ["Retry-After": "120"])
        }
        let client = github.client()
        let release = github.now.addingTimeInterval(120)

        await #expect(throws: GitHubError.rateLimited(until: release)) {
            _ = try await client.viewer()
        }
        // Still inside the window: refused locally, nothing reaches GitHub.
        github.advance(by: 60)
        await #expect(throws: GitHubError.rateLimited(until: release)) {
            _ = try await client.viewer()
        }
        #expect(github.requests.count == 1)

        // Past it: requests flow again.
        github.advance(by: 61)
        github.respond { _ in .json(#"{"login": "octocat"}"#) }
        #expect(try await client.viewer().login == "octocat")
        #expect(github.requests.count == 2)
    }

    @Test("an exhausted budget waits for the reset GitHub names")
    func waitsForReset() async {
        let github = StubGitHub()
        let reset = github.now.addingTimeInterval(900)
        github.respond { [self] _ in
            .json(
                #"{"message": "API rate limit exceeded for user."}"#,
                status: 403,
                headers: limitHeaders(resource: "core", remaining: 0, reset: reset.timeIntervalSince1970)
            )
        }
        let client = github.client()

        await #expect(throws: GitHubError.rateLimited(until: reset)) {
            _ = try await client.viewer()
        }
    }

    @Test("running out of GraphQL budget does not stop REST polling")
    func limitsAreIndependent() async throws {
        let github = StubGitHub()
        github.respond { request in
            request.path == "/graphql"
                ? .json(#"{"message": "rate limit"}"#, status: 429)
                : .json(#"{"login": "octocat"}"#)
        }
        let client = github.client()

        await #expect(throws: GitHubError.self) { _ = try await client.myOpenPullRequests() }
        #expect(try await client.viewer().login == "octocat")
    }

    @Test("a 403 that is not about rate limits stays a permission error")
    func permissionErrorIsNotARateLimit() async {
        let github = StubGitHub()
        github.respond { _ in .json(#"{"message": "Resource not accessible by personal access token"}"#, status: 403) }
        let client = github.client()

        await #expect(throws: GitHubError.http(status: 403, message: "Resource not accessible by personal access token")) {
            _ = try await client.viewer()
        }
    }
}

@Suite("The four verbs")
struct VerbTests {
    @Test("clearing approves every environment on the run")
    func approveBody() async throws {
        let github = StubGitHub()
        let client = github.client()

        try await client.approve(approval())

        let sent = try #require(github.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.path == "/repos/acme/web/actions/runs/42/pending_deployments")
        #expect(sent.json["environment_ids"] as? [Int] == [1, 2])
        #expect(sent.json["state"] as? String == "approved")
    }

    @Test("rejecting sends the reason")
    func rejectBody() async throws {
        let github = StubGitHub()
        let client = github.client()

        try await client.reject(approval(), comment: "wrong tag")

        let sent = try #require(github.requests.first)
        #expect(sent.json["state"] as? String == "rejected")
        #expect(sent.json["comment"] as? String == "wrong tag")
    }

    @Test("a merge is pinned to the commit Cleared saw")
    func mergeSendsHeadSHA() async throws {
        let github = StubGitHub()
        github.respond { _ in .json(#"{"merged": true, "message": "Pull Request successfully merged"}"#) }
        let client = github.client()

        try await client.merge(pullRequest(), method: .rebase)

        let sent = try #require(github.requests.first)
        #expect(sent.method == "PUT")
        #expect(sent.path == "/repos/acme/web/pulls/7/merge")
        #expect(sent.json["sha"] as? String == "abc123")
        #expect(sent.json["merge_method"] as? String == "rebase")
    }

    @Test("a push since the last poll surfaces GitHub's own explanation")
    func staleHeadIsRefused() async {
        let github = StubGitHub()
        let message = "Head branch was modified. Review and try the merge again."
        github.respond { _ in .json(#"{"message": "\#(message)"}"#, status: 409) }
        let client = github.client()

        await #expect(throws: GitHubError.http(status: 409, message: message)) {
            try await client.merge(pullRequest())
        }
        #expect(GitHubError.http(status: 409, message: message).localizedDescription == message)
    }

    @Test("a merge GitHub declines is an error, not a success")
    func declinedMerge() async {
        let github = StubGitHub()
        github.respond { _ in .json(#"{"merged": false, "message": "Required status check is expected."}"#) }
        let client = github.client()

        await #expect(throws: GitHubError.http(status: 405, message: "Required status check is expected.")) {
            try await client.merge(pullRequest())
        }
    }

    @Test("starting a workflow returns the run GitHub created")
    func dispatchReturnsRun() async throws {
        let github = StubGitHub()
        github.respond { _ in
            .json(#"{"workflow_run_id": 99, "run_url": "https://api.github.com/x", "html_url": "https://github.com/acme/web/actions/runs/99"}"#)
        }
        let client = github.client()
        let workflow = DispatchableWorkflow(repo: repo, workflowID: 5, name: "Deploy", path: ".github/workflows/deploy.yml")

        let run = try await client.dispatch(workflow, ref: "main", inputs: ["environment": "staging"])

        #expect(run?.absoluteString == "https://github.com/acme/web/actions/runs/99")
        let sent = try #require(github.requests.first)
        #expect(sent.path == "/repos/acme/web/actions/workflows/5/dispatches")
        #expect(sent.json["ref"] as? String == "main")
        #expect(sent.json["inputs"] as? [String: String] == ["environment": "staging"])
    }

    @Test("an empty 204 from an older API still counts as started")
    func dispatchWithoutBody() async throws {
        let github = StubGitHub()
        github.respond { _ in .json("", status: 204) }
        let client = github.client()
        let workflow = DispatchableWorkflow(repo: repo, workflowID: 5, name: "Deploy", path: ".github/workflows/deploy.yml")

        #expect(try await client.dispatch(workflow, ref: "main", inputs: [:]) == nil)
    }
}

@Suite("Reading the queue")
struct QueueReadingTests {
    @Test("only gates this user can clear are surfaced")
    func filtersToApprovableGates() async throws {
        let github = StubGitHub()
        github.respond { request in
            if request.path.contains("/runs/1/pending_deployments") {
                return .json(Fixture.pendingDeployments([(10, "staging", false), (11, "production", true)]))
            }
            if request.path.contains("/runs/2/pending_deployments") {
                return .json(Fixture.pendingDeployments([(10, "staging", false)]))
            }
            return .json(Fixture.runs([1, 2]))
        }
        let client = github.client()

        let approvals = try await client.pendingApprovals(in: repo)

        #expect(approvals.map(\.runID) == [1])
        #expect(approvals.first?.environmentIDs == [11])
    }

    @Test("pull requests carry GitHub's merge verdict and the repo's allowed methods")
    func decodesPullRequests() async throws {
        let github = StubGitHub()
        github.respond { _ in
            .json(Fixture.search([
                Fixture.pullRequest(number: 1),
                Fixture.pullRequest(number: 2, mergeState: "BLOCKED", review: "REVIEW_REQUIRED"),
                Fixture.pullRequest(number: 3, mergeCommit: false, rebase: false),
                "{}",
                "null",
            ]))
        }
        let client = github.client()

        let prs = try await client.myOpenPullRequests()

        #expect(prs.map(\.number) == [1, 2, 3])
        #expect(prs[0].isReadyToMerge)
        #expect(prs[0].headSHA == "abc1")
        #expect(prs[1].blockReason == "needs review")
        #expect(prs[2].allowedMethods == [.squash])
        #expect(prs[2].mergeMethod(preferring: .merge) == .squash)
    }

    @Test("only enabled workflows with a manual trigger can be started")
    func buildsWorkflowCatalog() async throws {
        let github = StubGitHub()
        let deploy = "name: Deploy\\non:\\n  workflow_dispatch:\\n    inputs:\\n      target:\\n        required: true\\n"
        let test = "name: Test\\non: [push]\\n"
        github.respond { request in
            if request.path == "/graphql" {
                return .json("""
                {"data": {"repository": {"defaultBranchRef": {"name": "trunk"}, "object": {"entries": [
                  {"path": ".github/workflows/deploy.yml", "object": {"text": "\(deploy)"}},
                  {"path": ".github/workflows/off.yml", "object": {"text": "\(deploy)"}},
                  {"path": ".github/workflows/test.yml", "object": {"text": "\(test)"}},
                  {"path": ".github/workflows/scripts", "object": {}}
                ]}}}}
                """)
            }
            return .json("""
            {"total_count": 4, "workflows": [
              {"id": 1, "name": "Deploy", "path": ".github/workflows/deploy.yml", "state": "active"},
              {"id": 2, "name": "Switched off", "path": ".github/workflows/off.yml", "state": "disabled_manually"},
              {"id": 3, "name": "Test", "path": ".github/workflows/test.yml", "state": "active"},
              {"id": 4, "name": "pages-build-deployment", "path": "dynamic/pages/pages-build-deployment", "state": "active"}
            ]}
            """)
        }
        let client = github.client()

        let catalog = try await client.workflowCatalog(in: repo)

        #expect(catalog.defaultBranch == "trunk")
        #expect(catalog.workflows.map(\.name) == ["Deploy"])
        #expect(catalog.workflows.first?.inputs.map(\.name) == ["target"])
    }

    @Test("a classic token without repo is flagged; a fine-grained token is trusted")
    func readsScopes() async throws {
        let github = StubGitHub()
        let client = github.client()

        github.respond { _ in .json(#"{"login": "octocat"}"#, headers: ["X-OAuth-Scopes": "gist, read:org"]) }
        #expect(try await client.viewer().canWrite == false)

        github.respond { _ in .json(#"{"login": "octocat"}"#, headers: ["X-OAuth-Scopes": "gist, repo, workflow"]) }
        #expect(try await client.viewer().canWrite)

        github.respond { _ in .json(#"{"login": "octocat"}"#) }
        let fineGrained = try await client.viewer()
        #expect(fineGrained.scopes == nil)
        #expect(fineGrained.canWrite)
    }
}
