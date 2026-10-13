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

    /// Identifies this hold for notifications. It includes the environments
    /// because one run can stop at several gates in turn: clearing staging
    /// and then being held at production is a second thing to tell you about.
    var announcementKey: String {
        "\(id)@" + environmentIDs.sorted().map(String.init).joined(separator: ",")
    }
}

/// Aggregate state of a pull request's checks, collapsed from GitHub's rollup.
enum CheckState: String, Sendable, Codable {
    case success, pending, failure, none

    var isGreen: Bool { self == .success }
}

/// GitHub's own verdict on whether a pull request can be merged right now.
/// It accounts for things a check rollup cannot see: required reviews, a
/// branch that must be up to date, rulesets.
enum MergeState: String, Sendable, Codable {
    case clean, hasHooks, unstable, blocked, behind, dirty, draft, unknown

    init(graphQL value: String?) {
        switch value {
        case "CLEAN": self = .clean
        case "HAS_HOOKS": self = .hasHooks
        case "UNSTABLE": self = .unstable
        case "BLOCKED": self = .blocked
        case "BEHIND": self = .behind
        case "DIRTY": self = .dirty
        case "DRAFT": self = .draft
        default: self = .unknown
        }
    }
}

enum ReviewDecision: String, Sendable, Codable {
    case approved, changesRequested, reviewRequired

    init?(graphQL value: String?) {
        switch value {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "REVIEW_REQUIRED": self = .reviewRequired
        default: return nil
        }
    }
}

enum MergeMethod: String, Sendable, Codable, CaseIterable {
    case squash, merge, rebase

    init?(graphQL value: String?) {
        switch value {
        case "SQUASH": self = .squash
        case "MERGE": self = .merge
        case "REBASE": self = .rebase
        default: return nil
        }
    }
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
    /// The commit the checks ran against. Sent with the merge so GitHub
    /// refuses if someone pushed after Cleared last looked.
    let headSHA: String
    let mergeState: MergeState
    let reviewDecision: ReviewDecision?
    let isInMergeQueue: Bool
    /// Merge methods the repository permits. Empty when unknown.
    let allowedMethods: [MergeMethod]
    let repoDefaultMethod: MergeMethod?

    init(
        repo: RepoRef,
        number: Int,
        title: String,
        branch: String,
        isDraft: Bool,
        checkState: CheckState,
        mergeable: String,
        htmlURL: URL,
        updatedAt: Date,
        headSHA: String = "",
        mergeState: MergeState = .clean,
        reviewDecision: ReviewDecision? = nil,
        isInMergeQueue: Bool = false,
        allowedMethods: [MergeMethod] = [],
        repoDefaultMethod: MergeMethod? = nil
    ) {
        self.repo = repo
        self.number = number
        self.title = title
        self.branch = branch
        self.isDraft = isDraft
        self.checkState = checkState
        self.mergeable = mergeable
        self.htmlURL = htmlURL
        self.updatedAt = updatedAt
        self.headSHA = headSHA
        self.mergeState = mergeState
        self.reviewDecision = reviewDecision
        self.isInMergeQueue = isInMergeQueue
        self.allowedMethods = allowedMethods
        self.repoDefaultMethod = repoDefaultMethod
    }

    var id: String { "\(repo.id)#\(number)" }

    /// Cleared only offers a merge button when nothing else stands in the way:
    /// checks green, no conflicts, not a draft, and GitHub agrees.
    var isReadyToMerge: Bool { blockReason == nil }

    /// Why there is no merge button, in the order someone would fix them.
    var blockReason: String? {
        if isDraft { return "draft" }
        if isInMergeQueue { return "in merge queue" }
        if mergeable == "conflicting" || mergeState == .dirty { return "conflicts" }
        switch checkState {
        case .failure: return "checks failed"
        case .pending: return "checks running"
        case .none: return "no checks"
        case .success: break
        }
        switch reviewDecision {
        case .changesRequested: return "changes requested"
        case .reviewRequired: return "needs review"
        case .approved, nil: break
        }
        switch mergeState {
        case .behind: return "behind base branch"
        case .blocked: return "blocked by branch rules"
        case .clean, .hasHooks, .unstable: break
        case .unknown, .dirty, .draft: return "GitHub is still checking"
        }
        return mergeable == "mergeable" ? nil : "GitHub is still checking"
    }

    /// The method to merge with: the user's preference where the repository
    /// allows it, otherwise the repository's own default. A repository that
    /// only permits squash would refuse a merge commit outright.
    func mergeMethod(preferring preferred: MergeMethod) -> MergeMethod {
        if allowedMethods.isEmpty || allowedMethods.contains(preferred) { return preferred }
        if let repoDefaultMethod, allowedMethods.contains(repoDefaultMethod) { return repoDefaultMethod }
        return allowedMethods[0]
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

/// One `workflow_dispatch` input, as declared in the workflow file.
struct WorkflowInput: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case string, number, boolean, environment
        case choice([String])
    }

    let name: String
    let description: String
    let kind: Kind
    let isRequired: Bool
    let defaultValue: String

    var id: String { name }
}

/// A workflow that can be started by hand (`on: workflow_dispatch`).
struct DispatchableWorkflow: Identifiable, Sendable, Hashable {
    let repo: RepoRef
    let workflowID: Int
    let name: String
    let path: String
    var inputs: [WorkflowInput] = []

    var id: String { "\(repo.id)#\(workflowID)" }
}

/// What the dispatch sheet needs for one repository.
struct WorkflowCatalog: Sendable, Hashable {
    let defaultBranch: String
    let workflows: [DispatchableWorkflow]
}

struct RateLimit: Sendable, Hashable {
    let remaining: Int
    let limit: Int
    let resetsAt: Date

    var isLow: Bool { remaining < 500 }
    var fraction: Double { limit > 0 ? Double(remaining) / Double(limit) : 1 }
}
