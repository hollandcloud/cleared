import AppKit
import Foundation
import UserNotifications

/// Tracks which items have already been announced, so each one notifies once
/// no matter how many polls observe it.
struct AnnouncementLedger: Sendable {
    private var seen: Set<String>?

    /// Returns the keys not seen on the previous call, then remembers `keys`.
    ///
    /// `announceFirstSight` decides what happens on the very first call: a
    /// deployment already held at launch still needs you, but a run that failed
    /// before Cleared started is not news.
    mutating func fresh(in keys: [String], announceFirstSight: Bool) -> [String] {
        defer { seen = Set(keys) }
        guard let seen else { return announceFirstSight ? keys : [] }
        return keys.filter { !seen.contains($0) }
    }

    /// Keys that were present last time and are gone now.
    func departed(from keys: [String]) -> [String] {
        guard let seen else { return [] }
        return Array(seen.subtracting(keys))
    }
}

/// Local notifications for things that enter the hold queue. Cleared only
/// notifies about work that is blocked on this user — never general activity.
@MainActor
final class Notifier: NSObject {
    static let shared = Notifier()

    private enum Category {
        static let hold = "net.hlnd.Cleared.hold"
        static let failure = "net.hlnd.Cleared.failure"
    }

    private enum Action {
        static let clear = "net.hlnd.Cleared.clear"
        static let rerun = "net.hlnd.Cleared.rerun"
    }

    private enum Info {
        static let item = "item"
        static let url = "url"
    }

    private weak var model: AppModel?
    /// Nil under test, so a test run can never post, clear, or prompt.
    private var center: UNUserNotificationCenter? {
        AppEnvironment.isRunningTests ? nil : .current()
    }
    private var authorized = false
    private var holds = AnnouncementLedger()
    private var failures = AnnouncementLedger()

    /// Registers the actions a notification can carry and routes clicks back
    /// to the model. A hold notification has a Clear button for the same
    /// reason the panel does: telling you something is waiting and then making
    /// you go find it is the problem Cleared exists to fix.
    func attach(to model: AppModel) {
        self.model = model
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.hold,
                actions: [UNNotificationAction(identifier: Action.clear, title: "Clear")],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.failure,
                actions: [UNNotificationAction(identifier: Action.rerun, title: "Re-run failed jobs")],
                intentIdentifiers: []
            ),
        ])
    }

    func requestAuthorizationIfNeeded() async {
        guard !AppEnvironment.isRunningTests else { return }
        // Fetched here rather than through `center`: a value read off this
        // actor cannot be handed to the system's async call under Swift 6.1.
        let center = UNUserNotificationCenter.current()
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorized = false
        }
    }

    /// Fires once per held deployment, and withdraws the notification once the
    /// hold is gone — a "Holding" alert for a gate someone already cleared is
    /// worse than no alert.
    func announceHolds(_ approvals: [PendingApproval]) {
        let keys = approvals.map(\.announcementKey)
        let departed = holds.departed(from: keys)
        let fresh = Set(holds.fresh(in: keys, announceFirstSight: true))

        if !departed.isEmpty {
            center?.removeDeliveredNotifications(withIdentifiers: departed)
        }
        guard authorized, Settings.shared.notifyOnHold else { return }

        for approval in approvals where fresh.contains(approval.announcementKey) {
            post(
                id: approval.announcementKey,
                category: Category.hold,
                title: "Holding · \(approval.repo.name)",
                body: "\(approval.runName) is waiting on \(approval.environmentNames).",
                item: approval.id,
                url: approval.htmlURL
            )
        }
    }

    /// Fires once per run that fails while Cleared is watching.
    func announceFailures(_ runs: [FailedRun]) {
        let fresh = Set(failures.fresh(in: runs.map(\.id), announceFirstSight: false))
        guard authorized, Settings.shared.notifyOnFailure else { return }

        for run in runs where fresh.contains(run.id) {
            post(
                id: run.id,
                category: Category.failure,
                title: "Failed · \(run.repo.name)",
                body: "\(run.name) on \(run.branch)",
                item: run.id,
                url: run.htmlURL
            )
        }
    }

    /// Forgets everything, so signing in as someone else starts clean.
    func reset() {
        holds = AnnouncementLedger()
        failures = AnnouncementLedger()
        center?.removeAllDeliveredNotifications()
    }

    private func post(id: String, category: String, title: String, body: String, item: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = [Info.item: item, Info.url: url.absoluteString]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center?.add(request)
    }

    private func handle(action: String, item: String?, url: URL?) async {
        switch action {
        case Action.clear:
            if let item { await model?.clearHold(withID: item) }
        case Action.rerun:
            if let item { await model?.rerunFailure(withID: item) }
        case UNNotificationDefaultActionIdentifier:
            if let url { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let item = info[Info.item] as? String
        let url = (info[Info.url] as? String).flatMap(URL.init(string:))
        await handle(action: action, item: item, url: url)
    }

    /// The system withholds a banner from whichever app is active. Without
    /// this, a hold that lands while the panel is open would arrive silently.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
