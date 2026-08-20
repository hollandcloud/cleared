import SwiftUI

/// One line in the queue: a status dot, a description, and the button that
/// resolves it. Every row in Cleared can be acted on — nothing is here to be
/// admired, only to be cleared.
struct ActionRow<Trailing: View>: View {
    let dot: Color
    let title: String
    let subtitle: String
    let isBusy: Bool
    let openURL: URL
    @ViewBuilder var trailing: Trailing

    @Environment(\.openURL) private var open
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .help("Open on GitHub")
    }
}

/// The button that does the thing. Amber for a hold, green for a merge.
struct ClearButton: View {
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(tint)
    }
}
