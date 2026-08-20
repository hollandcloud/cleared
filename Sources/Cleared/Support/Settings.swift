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
        static let confirmMerge = "confirmBeforeMerge"
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
            Key.confirmMerge: false,
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

    var mergeMethod: String {
        get { access(keyPath: \.mergeMethod); return defaults.string(forKey: Key.mergeMethod) ?? "squash" }
        set { withMutation(keyPath: \.mergeMethod) { defaults.set(newValue, forKey: Key.mergeMethod) } }
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

    var confirmBeforeMerge: Bool {
        get { access(keyPath: \.confirmBeforeMerge); return defaults.bool(forKey: Key.confirmMerge) }
        set { withMutation(keyPath: \.confirmBeforeMerge) { defaults.set(newValue, forKey: Key.confirmMerge) } }
    }

    func toggleExclusion(_ repo: RepoRef) {
        var set = excludedRepos
        if set.contains(repo.id) { set.remove(repo.id) } else { set.insert(repo.id) }
        excludedRepos = set
    }
}

extension TimeInterval {
    func clamped(_ low: TimeInterval, _ high: TimeInterval) -> TimeInterval {
        Swift.min(Swift.max(self, low), high)
    }
}
