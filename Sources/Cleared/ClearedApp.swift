import SwiftUI

@main
struct ClearedApp: App {
#if DEBUG
    @NSApplicationDelegateAdaptor(PreviewLauncher.self) private var launcher
#endif
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
                .task { await model.start() }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

#if DEBUG
/// `open Cleared.app --args --ui-preview` renders the panel in an ordinary
/// window against sample data.
///
/// Laying out the queue against real GitHub state means waiting for a
/// deployment to actually be held — the rare event the whole app exists to
/// catch — so the panel would otherwise be near-impossible to iterate on.
final class PreviewLauncher: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--ui-preview") else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth + 48, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cleared · panel preview"
        window.contentView = NSHostingView(rootView: PreviewHarness())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct PreviewHarness: View {
    enum Fixture: String, CaseIterable {
        case full = "Full queue", overflow = "Overflowing", empty = "All clear"

        /// Matched on the case name, not the display label — "empty" has to
        /// select `.empty`, whose label is "All clear".
        var key: String {
            switch self {
            case .full: "full"
            case .overflow: "overflow"
            case .empty: "empty"
            }
        }

        /// `--ui-preview overflow` opens straight into that fixture, so a
        /// screenshot needs no clicking.
        static func fromCommandLine(_ args: [String] = CommandLine.arguments) -> Fixture {
            guard let index = args.firstIndex(of: "--ui-preview"), args.count > index + 1 else { return .full }
            let requested = args[index + 1].lowercased()
            return allCases.first { $0.key == requested } ?? .full
        }
    }

    @State private var model: AppModel
    @State private var fixture: Fixture

    init() {
        let start = Fixture.fromCommandLine()
        let model = AppModel()
        model.loadSample(empty: start == .empty, overflow: start == .overflow)
        _model = SwiftUI.State(initialValue: model)
        _fixture = SwiftUI.State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $fixture) {
                ForEach(Fixture.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: fixture) { _, new in
                model.loadSample(empty: new == .empty, overflow: new == .overflow)
            }

            MenuPanel(model: model)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                .shadow(radius: 14)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
#endif
