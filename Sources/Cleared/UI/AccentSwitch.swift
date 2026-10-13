import SwiftUI

/// A switch that shows the system accent colour when it is on, whatever state
/// its window is in.
///
/// AppKit draws its own switch grey in any window that is not key, and a menu
/// bar panel often is not — so in Settings "on" and "off" differed only by
/// where the knob sat. This one is drawn here, and takes its colour from the
/// accent the user picked in System Settings.
struct AccentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            AccentSwitch(isOn: configuration.$isOn)
        } label: {
            configuration.label
        }
        // Presented to VoiceOver as the ordinary toggle it stands in for.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

private struct AccentSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    private let track = CGSize(width: 36, height: 20)
    private let knob = CGSize(width: 22, height: 16)

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.18))
                .frame(width: track.width, height: track.height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: knob.width, height: knob.height)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                        .padding(.horizontal, (track.height - knob.height) / 2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
