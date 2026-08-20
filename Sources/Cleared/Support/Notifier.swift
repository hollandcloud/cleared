import Foundation
import UserNotifications

/// Local notifications for things that enter the hold queue. Cleared only
/// notifies about work that is blocked on this user — never general activity.
@MainActor
final class Notifier {
    static let shared = Notifier()

    private var authorized = false
    private var announced: Set<String> = []

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorized = false
        }
    }

    /// Fires once per held deployment, no matter how many polls observe it.
    func announceHolds(_ approvals: [PendingApproval]) async {
        guard authorized, Settings.shared.notifyOnHold else { return }
        let current = Set(approvals.map(\.id))
        let fresh = approvals.filter { !announced.contains($0.id) }
        announced = current

        for approval in fresh {
            await post(
                id: approval.id,
                title: "Holding · \(approval.repo.name)",
                body: "\(approval.runName) is waiting on \(approval.environmentNames)."
            )
        }
    }

    func announceFailure(_ run: FailedRun) async {
        guard authorized, Settings.shared.notifyOnFailure else { return }
        await post(id: run.id, title: "Failed · \(run.repo.name)", body: "\(run.name) on \(run.branch)")
    }

    private func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
