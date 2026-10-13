import Foundation

#if DEBUG
/// Sample data for SwiftUI previews and the `--ui-preview` harness.
///
/// Laying the panel out against real GitHub state means waiting for a
/// deployment to actually be held, which is exactly the rare event the app
/// exists to catch. These fixtures cover the shapes that matter: a long title
/// that has to truncate, several environments on one gate, and enough rows to
/// push the queue past its height cap.
enum SampleData {
    static let repos = [
        RepoRef(owner: "acme", name: "platform"),
        RepoRef(owner: "acme", name: "web"),
        RepoRef(owner: "acme", name: "infra"),
    ]

    static var approvals: [PendingApproval] {
        [
            PendingApproval(
                repo: repos[0],
                runID: 9_001,
                runName: "Deploy Production",
                branch: "main",
                environments: [.init(id: 1, name: "production")],
                waitingSince: Date().addingTimeInterval(-380),
                htmlURL: URL(string: "https://github.com/acme/platform/actions/runs/9001")!
            ),
            PendingApproval(
                repo: repos[2],
                runID: 9_002,
                runName: "Apply Terraform",
                branch: "main",
                environments: [.init(id: 2, name: "production"), .init(id: 3, name: "prod-eu")],
                waitingSince: Date().addingTimeInterval(-14_400),
                htmlURL: URL(string: "https://github.com/acme/infra/actions/runs/9002")!
            ),
        ]
    }

    static var pullRequests: [PullRequestSummary] {
        [
            pr(repos[0], 412, "feat(api): generate the OpenAPI 3.1 spec from the route tree", .success, "mergeable"),
            pr(repos[1], 118, "fix(web): stale chunk reload on deploy", .success, "mergeable"),
            pr(repos[0], 411, "chore: bump actions to node24", .success, "mergeable"),
            pr(repos[1], 117, "refactor(web): collapse the settings form into one grid", .pending, "mergeable"),
            pr(repos[2], 55, "feat(infra): self-hosted runner pool", .failure, "mergeable"),
            pr(repos[0], 409, "docs: rewrite the contributing guide", .success, "conflicting"),
            pr(repos[2], 54, "feat(infra): rotate the deploy keys", .success, "mergeable", review: .reviewRequired),
        ]
    }

    /// Enough rows to push the queue past its height cap, so the scroll
    /// behaviour can be checked without waiting for a busy day.
    static var manyPullRequests: [PullRequestSummary] {
        pullRequests + (1...10).map { index in
            pr(repos[index % 3], 500 + index, "feat: additional change number \(index) to exercise scrolling", .success, "mergeable")
        }
    }

    static var failures: [FailedRun] {
        [
            FailedRun(
                repo: repos[2],
                runID: 8_800,
                name: "Validate Bicep Templates",
                branch: "feat/runner-pool",
                htmlURL: URL(string: "https://github.com/acme/infra/actions/runs/8800")!,
                finishedAt: Date().addingTimeInterval(-900)
            ),
        ]
    }

    /// A repository's startable workflows, covering every kind of input the
    /// dispatch sheet has to draw.
    static var catalog: WorkflowCatalog {
        WorkflowCatalog(
            defaultBranch: "main",
            workflows: [
                DispatchableWorkflow(
                    repo: repos[0],
                    workflowID: 1,
                    name: "Deploy",
                    path: ".github/workflows/deploy.yml",
                    inputs: [
                        WorkflowInput(
                            name: "environment",
                            description: "Where to deploy.",
                            kind: .choice(["staging", "production"]),
                            isRequired: true,
                            defaultValue: "staging"
                        ),
                        WorkflowInput(name: "version", description: "Tag to ship, e.g. v1.2.3.", kind: .string, isRequired: true, defaultValue: ""),
                        WorkflowInput(name: "dry_run", description: "Plan only; change nothing.", kind: .boolean, isRequired: false, defaultValue: "true"),
                        WorkflowInput(name: "replicas", description: "", kind: .number, isRequired: false, defaultValue: "3"),
                    ]
                ),
                DispatchableWorkflow(repo: repos[0], workflowID: 2, name: "Nightly rebuild", path: ".github/workflows/nightly.yml"),
                DispatchableWorkflow(repo: repos[0], workflowID: 3, name: "Rotate credentials", path: ".github/workflows/rotate.yml"),
            ]
        )
    }

    private static func pr(
        _ repo: RepoRef, _ number: Int, _ title: String,
        _ checks: CheckState, _ mergeable: String,
        review: ReviewDecision? = nil
    ) -> PullRequestSummary {
        PullRequestSummary(
            repo: repo,
            number: number,
            title: title,
            branch: "branch/\(number)",
            isDraft: false,
            checkState: checks,
            mergeable: mergeable,
            htmlURL: URL(string: "https://github.com/\(repo.fullName)/pull/\(number)")!,
            updatedAt: Date().addingTimeInterval(-Double(number) * 60),
            mergeState: review == .reviewRequired ? .blocked : .clean,
            reviewDecision: review
        )
    }
}

@MainActor
extension AppModel {
    /// A model wired to sample data, with no network behind it.
    static func preview(empty: Bool = false) -> AppModel {
        let model = AppModel()
        model.loadSample(empty: empty)
        return model
    }
}
#endif
