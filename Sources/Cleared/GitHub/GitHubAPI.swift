import Foundation

// MARK: - Wire types

private struct RunsPage: Decodable, Sendable {
    struct Run: Decodable, Sendable {
        let id: Int
        let name: String?
        let head_branch: String?
        let status: String?
        let conclusion: String?
        let created_at: Date
        let updated_at: Date
        let html_url: String
    }
    let total_count: Int
    let workflow_runs: [Run]
}

private struct PendingDeploymentDTO: Decodable, Sendable {
    struct Env: Decodable, Sendable { let id: Int; let name: String }
    let environment: Env
    let current_user_can_approve: Bool
    let wait_timer: Int?
}

private struct WorkflowsPage: Decodable, Sendable {
    struct Workflow: Decodable, Sendable {
        let id: Int
        let name: String
        let path: String
        let state: String
    }
    let workflows: [Workflow]
}

private struct RepoDTO: Decodable, Sendable {
    struct Owner: Decodable, Sendable { let login: String }
    let name: String
    let owner: Owner
    let archived: Bool
    let disabled: Bool?
    let pushed_at: Date?
}

private struct MergeResult: Decodable, Sendable {
    let merged: Bool?
    let message: String?
}

// MARK: - Read + write operations

extension GitHubClient {

    /// Runs held at an environment gate in one repository.
    ///
    /// Uses the ETag cache: a repository with nothing waiting returns an
    /// identical body forever, so it answers 304 and costs no rate limit.
    func pendingApprovals(in repo: RepoRef) async throws -> [PendingApproval] {
        let page: RunsPage = try await get(
            RunsPage.self,
            "repos/\(repo.owner)/\(repo.name)/actions/runs?status=waiting&per_page=20",
            useCache: true
        )
        guard !page.workflow_runs.isEmpty else { return [] }

        var approvals: [PendingApproval] = []
        for run in page.workflow_runs {
            let deployments: [PendingDeploymentDTO] = try await get(
                [PendingDeploymentDTO].self,
                "repos/\(repo.owner)/\(repo.name)/actions/runs/\(run.id)/pending_deployments"
            )
            // Only surface gates this user can actually clear. A run held for
            // someone else is noise, not an action.
            let mine = deployments.filter(\.current_user_can_approve)
            guard !mine.isEmpty, let url = URL(string: run.html_url) else { continue }

            approvals.append(
                PendingApproval(
                    repo: repo,
                    runID: run.id,
                    runName: run.name ?? "Workflow run",
                    branch: run.head_branch ?? "—",
                    environments: mine.map { .init(id: $0.environment.id, name: $0.environment.name) },
                    waitingSince: run.created_at,
                    htmlURL: url
                )
            )
        }
        return approvals
    }

    /// Clears a held deployment. This is the action the whole app exists for.
    func approve(_ approval: PendingApproval, comment: String = "Cleared from the menu bar") async throws {
        struct Body: Encodable, Sendable {
            let environment_ids: [Int]
            let state: String
            let comment: String
        }
        try await rest(
            "POST",
            "repos/\(approval.repo.owner)/\(approval.repo.name)/actions/runs/\(approval.runID)/pending_deployments",
            body: Body(environment_ids: approval.environmentIDs, state: "approved", comment: comment)
        )
    }

    /// Rejects a held deployment.
    func reject(_ approval: PendingApproval, comment: String) async throws {
        struct Body: Encodable, Sendable {
            let environment_ids: [Int]
            let state: String
            let comment: String
        }
        try await rest(
            "POST",
            "repos/\(approval.repo.owner)/\(approval.repo.name)/actions/runs/\(approval.runID)/pending_deployments",
            body: Body(environment_ids: approval.environmentIDs, state: "rejected", comment: comment)
        )
    }

    /// Every open pull request you authored, with check state, in one request.
    func myOpenPullRequests(limit: Int = 50) async throws -> [PullRequestSummary] {
        struct Payload: Decodable, Sendable {
            struct Search: Decodable, Sendable { let nodes: [Node?] }
            struct Node: Decodable, Sendable {
                struct Repo: Decodable, Sendable {
                    struct Owner: Decodable, Sendable { let login: String }
                    let name: String
                    let owner: Owner
                }
                struct Commits: Decodable, Sendable {
                    struct CommitNode: Decodable, Sendable {
                        struct Commit: Decodable, Sendable {
                            struct Rollup: Decodable, Sendable { let state: String }
                            let statusCheckRollup: Rollup?
                        }
                        let commit: Commit
                    }
                    let nodes: [CommitNode]
                }
                let number: Int
                let title: String
                let url: String
                let isDraft: Bool
                let headRefName: String
                let updatedAt: Date
                let mergeable: String
                let repository: Repo
                let commits: Commits
            }
            let search: Search
        }

        let query = """
        query($q: String!) {
          search(query: $q, type: ISSUE, first: \(limit)) {
            nodes {
              ... on PullRequest {
                number title url isDraft headRefName updatedAt mergeable
                repository { name owner { login } }
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
              }
            }
          }
        }
        """

        let payload: Payload = try await graphQL(
            Payload.self,
            query: query,
            variables: ["q": "is:pr is:open author:@me archived:false"]
        )

        return payload.search.nodes.compactMap { node -> PullRequestSummary? in
            guard let node, let url = URL(string: node.url) else { return nil }
            let rollup = node.commits.nodes.first?.commit.statusCheckRollup?.state
            let checks: CheckState = switch rollup {
            case "SUCCESS": .success
            case "PENDING", "EXPECTED": .pending
            case "FAILURE", "ERROR": .failure
            default: .none
            }
            return PullRequestSummary(
                repo: RepoRef(owner: node.repository.owner.login, name: node.repository.name),
                number: node.number,
                title: node.title,
                branch: node.headRefName,
                isDraft: node.isDraft,
                checkState: checks,
                mergeable: node.mergeable.lowercased(),
                htmlURL: url,
                updatedAt: node.updatedAt
            )
        }
    }

    /// Squash-merges. Squash is the default because a squash commit takes the PR
    /// title, which is what semantic-release reads to pick the next version.
    func merge(_ pr: PullRequestSummary, method: String = "squash") async throws {
        struct Body: Encodable, Sendable { let merge_method: String }
        let response = try await rest(
            "PUT",
            "repos/\(pr.repo.owner)/\(pr.repo.name)/pulls/\(pr.number)/merge",
            body: Body(merge_method: method)
        )
        let result = try Self.decode(MergeResult.self, from: response.data)
        if result.merged == false {
            throw GitHubError.http(status: 405, message: result.message ?? "GitHub declined the merge.")
        }
    }

    /// Recently failed runs in one repository.
    func recentFailures(in repo: RepoRef, limit: Int = 5) async throws -> [FailedRun] {
        let page: RunsPage = try await get(
            RunsPage.self,
            "repos/\(repo.owner)/\(repo.name)/actions/runs?status=failure&per_page=\(limit)",
            useCache: true
        )
        return page.workflow_runs.compactMap { run in
            guard let url = URL(string: run.html_url) else { return nil }
            return FailedRun(
                repo: repo,
                runID: run.id,
                name: run.name ?? "Workflow run",
                branch: run.head_branch ?? "—",
                htmlURL: url,
                finishedAt: run.updated_at
            )
        }
    }

    func rerunFailedJobs(_ run: FailedRun) async throws {
        try await rest("POST", "repos/\(run.repo.owner)/\(run.repo.name)/actions/runs/\(run.runID)/rerun-failed-jobs")
    }

    /// Workflows in a repository that declare `on: workflow_dispatch`.
    func dispatchableWorkflows(in repo: RepoRef) async throws -> [DispatchableWorkflow] {
        let page: WorkflowsPage = try await get(
            WorkflowsPage.self,
            "repos/\(repo.owner)/\(repo.name)/actions/workflows?per_page=100",
            useCache: true
        )
        return page.workflows
            .filter { $0.state == "active" }
            .map { DispatchableWorkflow(repo: repo, workflowID: $0.id, name: $0.name, path: $0.path) }
    }

    func dispatch(_ workflow: DispatchableWorkflow, ref: String, inputs: [String: String]) async throws {
        struct Body: Encodable, Sendable { let ref: String; let inputs: [String: String] }
        try await rest(
            "POST",
            "repos/\(workflow.repo.owner)/\(workflow.repo.name)/actions/workflows/\(workflow.workflowID)/dispatches",
            body: Body(ref: ref, inputs: inputs)
        )
    }

    /// Repositories the signed-in user has pushed to recently.
    ///
    /// Discovery is deliberate: Cleared ships with no repository list, so the
    /// source reveals nothing about what anyone tracks, and repos that see one
    /// pull request a month get picked up without being added by hand.
    func discoverRepos(activeWithinDays days: Int, limit: Int) async throws -> [RepoRef] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var found: [(RepoRef, Date)] = []

        for page in 1...3 {
            let repos: [RepoDTO] = try await get(
                [RepoDTO].self,
                "user/repos?affiliation=owner,organization_member,collaborator&sort=pushed&direction=desc&per_page=100&page=\(page)"
            )
            if repos.isEmpty { break }
            for repo in repos where !repo.archived && (repo.disabled != true) {
                guard let pushed = repo.pushed_at else { continue }
                if pushed >= cutoff {
                    found.append((RepoRef(owner: repo.owner.login, name: repo.name), pushed))
                }
            }
            // Sorted by pushed desc, so once a page falls entirely past the
            // cutoff there is nothing newer further on.
            if let last = repos.last?.pushed_at, last < cutoff { break }
            if repos.count < 100 { break }
        }

        return found
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func viewerLogin() async throws -> String {
        struct User: Decodable, Sendable { let login: String }
        let user: User = try await get(User.self, "user")
        return user.login
    }
}
