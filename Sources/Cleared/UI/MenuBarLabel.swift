import SwiftUI

/// The menu bar itself. Shows a count only when something is actually waiting,
/// so an empty queue is a quiet menu bar rather than a permanent badge.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if model.pendingCount > 0 {
                Text("\(model.pendingCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var symbol: String {
        switch model.phase {
        case .needsToken, .failed: "exclamationmark.triangle"
        case .connecting: "ellipsis.circle"
        case .ready: model.approvals.isEmpty
            ? (model.readyToMerge.isEmpty ? "checkmark.circle" : "arrow.triangle.merge")
            : "airplane.circle.fill"
        }
    }

    private var accessibilityText: String {
        if model.approvals.isEmpty && model.readyToMerge.isEmpty { return "Cleared. All clear." }
        var parts: [String] = []
        if !model.approvals.isEmpty { parts.append("\(model.approvals.count) holding") }
        if !model.readyToMerge.isEmpty { parts.append("\(model.readyToMerge.count) ready to merge") }
        return "Cleared. " + parts.joined(separator: ", ")
    }
}
