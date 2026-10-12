import Foundation
import Observation

/// User preferences. Repository selections live here, in this user's own
/// defaults — never in the repository, so the public source stays free of
/// anyone's private repo names.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let approvalInterval = "approvalPollSeconds"
        static let backgroundMultiplier = "backgroundPollMultiplier"
        static let discoveryDays = "discoveryActiveDays"
        static let repoLimit = "discoveryRepoLimit"
        static let excluded = "excludedRepos"
        static let pinned = "pinnedRepos"
        static let mergeMethod = "mergeMethod"
        static let notifyOnHold = "notifyOnHold"
        static let notifyOnFailure = "notifyOnFailure"
        static let showFailures = "showFailures"
        static let confirmActions = "confirmActions"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.approvalInterval: 30,
            Key.backgroundMultiplier: 4,
            Key.discoveryDays: 90,
            Key.repoLimit: 20,
            Key.mergeMethod: "squash",
            Key.notifyOnHold: true,
            Key.notifyOnFailure: false,
            Key.showFailures: true,
            Key.confirmActions: false,
        ])
    }

    /// How often to check for held deployments while the menu is open.
    var approvalInterval: TimeInterval {
        get { access(keyPath: \.approvalInterval); return TimeInterval(defaults.integer(forKey: Key.approvalInterval)) }
        set { withMutation(keyPath: \.approvalInterval) { defaults.set(Int(newValue.clamped(10, 300)), forKey: Key.approvalInterval) } }
    }

    /// Polling slows by this factor when nobody is looking at the menu.
    var backgroundMultiplier: Int {
        get { access(keyPath: \.backgroundMultiplier); return max(1, defaults.integer(forKey: Key.backgroundMultiplier)) }
        set { withMutation(keyPath: \.backgroundMultiplier) { defaults.set(max(1, newValue), forKey: Key.backgroundMultiplier) } }
    }

    var discoveryDays: Int {
        get { access(keyPath: \.discoveryDays); return max(1, defaults.integer(forKey: Key.discoveryDays)) }
        set { withMutation(keyPath: \.discoveryDays) { defaults.set(max(1, newValue), forKey: Key.discoveryDays) } }
    }

    var repoLimit: Int {
        get { access(keyPath: \.repoLimit); return max(1, defaults.integer(forKey: Key.repoLimit)) }
        set { withMutation(keyPath: \.repoLimit) { defaults.set(max(1, newValue), forKey: Key.repoLimit) } }
    }

    var excludedRepos: Set<String> {
        get { access(keyPath: \.excludedRepos); return Set(defaults.stringArray(forKey: Key.excluded) ?? []) }
        set { withMutation(keyPath: \.excludedRepos) { defaults.set(Array(newValue).sorted(), forKey: Key.excluded) } }
    }

    var pinnedRepos: [String] {
        get { access(keyPath: \.pinnedRepos); return defaults.stringArray(forKey: Key.pinned) ?? [] }
        set { withMutation(keyPath: \.pinnedRepos) { defaults.set(newValue, forKey: Key.pinned) } }
    }

    /// The method to merge with where a repository allows it. A repository
    /// that does not falls back to its own default.
    var mergeMethod: MergeMethod {
        get {
            access(keyPath: \.mergeMethod)
            return defaults.string(forKey: Key.mergeMethod).flatMap(MergeMethod.init(rawValue:)) ?? .squash
        }
        set { withMutation(keyPath: \.mergeMethod) { defaults.set(newValue.rawValue, forKey: Key.mergeMethod) } }
    }

    var notifyOnHold: Bool {
        get { access(keyPath: \.notifyOnHold); return defaults.bool(forKey: Key.notifyOnHold) }
        set { withMutation(keyPath: \.notifyOnHold) { defaults.set(newValue, forKey: Key.notifyOnHold) } }
    }

    var notifyOnFailure: Bool {
        get { access(keyPath: \.notifyOnFailure); return defaults.bool(forKey: Key.notifyOnFailure) }
        set { withMutation(keyPath: \.notifyOnFailure) { defaults.set(newValue, forKey: Key.notifyOnFailure) } }
    }

    var showFailures: Bool {
        get { access(keyPath: \.showFailures); return defaults.bool(forKey: Key.showFailures) }
        set { withMutation(keyPath: \.showFailures) { defaults.set(newValue, forKey: Key.showFailures) } }
    }

    /// Clear and Merge take a second click when this is on. Off by default:
    /// one click is the point, and both buttons only appear when GitHub
    /// already agrees the action is allowed.
    var confirmActions: Bool {
        get { access(keyPath: \.confirmActions); return defaults.bool(forKey: Key.confirmActions) }
        set { withMutation(keyPath: \.confirmActions) { defaults.set(newValue, forKey: Key.confirmActions) } }
    }

    func setExcluded(_ excluded: Bool, _ repoID: String) {
        var set = excludedRepos
        if excluded { set.insert(repoID) } else { set.remove(repoID) }
        excludedRepos = set
    }

    /// Pins a repository so it is watched however quiet it has been. Returns
    /// false when the text is not `owner/name`.
    @discardableResult
    func pin(_ fullName: String) -> Bool {
        guard let repo = RepoRef(fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        if !pinnedRepos.contains(where: { $0.caseInsensitiveCompare(repo.id) == .orderedSame }) {
            pinnedRepos.append(repo.id)
        }
        // Pinning something that was ignored means it is wanted after all.
        setExcluded(false, repo.id)
        return true
    }

    func unpin(_ repoID: String) {
        pinnedRepos.removeAll { $0 == repoID }
    }
}

extension TimeInterval {
    func clamped(_ low: TimeInterval, _ high: TimeInterval) -> TimeInterval {
        Swift.min(Swift.max(self, low), high)
    }
}
