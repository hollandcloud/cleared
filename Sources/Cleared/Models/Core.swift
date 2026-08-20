import Foundation

/// A repository Cleared watches. Always supplied at runtime by discovery or by
/// the user — never hard-coded, so a public checkout of this source reveals
/// nothing about which repositories anyone actually tracks.
struct RepoRef: Hashable, Sendable, Codable, Identifiable {
    let owner: String
    let name: String

    var id: String { "\(owner)/\(name)" }
    var fullName: String { id }

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parses "owner/name". Returns nil for anything else.
    init?(fullName: String) {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        self.owner = String(parts[0])
        self.name = String(parts[1])
    }
}

/// A deployment held at an environment gate, waiting for a required reviewer.
/// This is the item Cleared exists for.
struct PendingApproval: Identifiable, Sendable, Hashable {
    struct Environment: Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
    }

    let repo: RepoRef
    let runID: Int
    let runName: String
    let branch: String
    let environments: [Environment]
    let waitingSince: Date
    let htmlURL: URL

    var id: String { "\(repo.id)#\(runID)" }
    var environmentNames: String {
        environments.map(\.name).joined(separator: ", ")
    }
    var environmentIDs: [Int] { environments.map(\.id) }
}

/// Aggregate state of a pull request's checks, collapsed from GitHub's rollup.
enum CheckState: String, Sendable, Codable {
    case success, pending, failure, none

    var isGreen: Bool { self == .success }
}

struct PullRequestSummary: Identifiable, Sendable, Hashable {
    let repo: RepoRef
    let number: Int
    let title: String
    let branch: String
    let isDraft: Bool
    let checkState: CheckState
    /// GitHub's MERGEABLE / CONFLICTING / UNKNOWN, lowercased.
    let mergeable: String
    let htmlURL: URL
    let updatedAt: Date

    var id: String { "\(repo.id)#\(number)" }

    /// Cleared only offers a merge button when nothing else stands in the way:
    /// checks green, no conflicts, not a draft.
    var isReadyToMerge: Bool {
        checkState.isGreen && !isDraft && mergeable == "mergeable"
    }

    var blockReason: String? {
        if isDraft { return "draft" }
        if mergeable == "conflicting" { return "conflicts" }
        switch checkState {
        case .failure: return "checks failed"
        case .pending: return "checks running"
        case .none: return "no checks"
        case .success: return nil
        }
    }
}

struct FailedRun: Identifiable, Sendable, Hashable {
    let repo: RepoRef
    let runID: Int
    let name: String
    let branch: String
    let htmlURL: URL
    let finishedAt: Date

    var id: String { "\(repo.id)#\(runID)" }
}

/// A workflow that can be started by hand (`on: workflow_dispatch`).
struct DispatchableWorkflow: Identifiable, Sendable, Hashable {
    let repo: RepoRef
    let workflowID: Int
    let name: String
    let path: String

    var id: String { "\(repo.id)#\(workflowID)" }
}

struct RateLimit: Sendable, Hashable {
    let remaining: Int
    let limit: Int
    let resetsAt: Date

    var isLow: Bool { remaining < 500 }
    var fraction: Double { limit > 0 ? Double(remaining) / Double(limit) : 1 }
}
