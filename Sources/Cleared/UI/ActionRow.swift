import SwiftUI

/// Something a row can do besides its main button, offered on right-click.
struct RowAction: Identifiable {
    let title: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

/// One line in the queue: a status dot, a description, and the button that
/// resolves it. Every row in Cleared can be acted on — nothing is here to be
/// admired, only to be cleared.
struct ActionRow<Trailing: View>: View {
    let dot: Color
    let title: String
    let subtitle: String
    let isBusy: Bool
    let openURL: URL
    var actions: [RowAction] = []
    @ViewBuilder var trailing: Trailing

    @Environment(\.openURL) private var open
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // Tail truncation, not middle: the front of a PR title carries
                // the conventional-commit type and scope, which is the part
                // worth keeping when it doesn't fit.
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // Middle truncation here, because a subtitle is owner/repo ·
                // branch and both ends identify it.
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
            .accessibilityAction { open(openURL) }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 52)
            } else {
                trailing
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { open(openURL) }
        .contextMenu {
            ForEach(actions) { action in
                Button(action.title, role: action.isDestructive ? .destructive : nil, action: action.perform)
            }
            if !actions.isEmpty { Divider() }
            Button("Open on GitHub") { open(openURL) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(openURL.absoluteString, forType: .string)
            }
        }
        .help("\(title)\n\(subtitle)\n\nClick to open on GitHub")
    }
}

/// The button that does the thing. Amber for a hold, green for a merge.
///
/// With `confirms` on, the first click arms the button and the second one
/// fires it. Arming lapses after a few seconds, so a button left armed cannot
/// be set off by a stray click later.
struct ClearButton: View {
    let label: String
    let tint: Color
    var confirms = false
    var shortcut: KeyEquivalent?
    let action: () -> Void

    @State private var isArmed = false

    var body: some View {
        Button {
            if confirms, !isArmed {
                isArmed = true
            } else {
                isArmed = false
                action()
            }
        } label: {
            Text(isArmed ? "Sure?" : label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(isArmed ? Theme.stop : tint)
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0, modifiers: .command) })
        .task(id: isArmed) {
            guard isArmed else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { isArmed = false }
        }
        .accessibilityLabel(isArmed ? "Confirm \(label)" : label)
    }
}
