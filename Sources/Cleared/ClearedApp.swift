import SwiftUI

@main
struct ClearedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the model, so polling starts when the app launches.
///
/// A window-style `MenuBarExtra` does not build its content until the icon is
/// first clicked. Starting from the panel would mean an app launched at login
/// watches nothing — and announces nothing — until someone opens it, which is
/// the opposite of what a hold notifier is for.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
#if DEBUG
    private var previewWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if CommandLine.arguments.contains("--ui-preview") {
            openPreview()
            return
        }
#endif
        // The unit tests run hosted inside the app. They must never read the
        // Keychain, prompt for notifications, or reach GitHub.
        guard !AppEnvironment.isRunningTests else { return }

        Notifier.shared.attach(to: model)
        Task { await model.start() }
    }
}

enum AppEnvironment {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// True in the App Store build. The system sets this variable for every
    /// sandboxed process, so one binary can tell which way it was built.
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// "0.4.0" — read from the bundle so the User-Agent and the Settings
    /// footer can never drift from `MARKETING_VERSION`.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

private struct SandboxedBuildKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.isSandboxed
}

extension EnvironmentValues {
    /// Whether to show the App Store build's interface. An environment value
    /// so the preview harness can show that interface from an ordinary build.
    var isSandboxedBuild: Bool {
        get { self[SandboxedBuildKey.self] }
        set { self[SandboxedBuildKey.self] = newValue }
    }
}

#if DEBUG
extension AppDelegate {
    /// `open Cleared.app --args --ui-preview` renders the panel in an ordinary
    /// window against sample data.
    ///
    /// Laying out the queue against real GitHub state means waiting for a
    /// deployment to actually be held — the rare event the whole app exists to
    /// catch — so the panel would otherwise be near-impossible to iterate on.
    private func openPreview() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth + 120, height: 820),
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
        previewWindow = window
    }
}

struct PreviewHarness: View {
    enum Fixture: String, CaseIterable {
        case full = "Full queue", overflow = "Overflowing", empty = "All clear"
        case connect = "Connect", connectAppStore = "App Store"

        /// Matched on the case name, not the display label — "empty" has to
        /// select `.empty`, whose label is "All clear".
        var key: String {
            switch self {
            case .full: "full"
            case .overflow: "overflow"
            case .empty: "empty"
            case .connect: "connect"
            case .connectAppStore: "connect-appstore"
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
        Self.show(start, in: model)
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
                Self.show(new, in: model)
            }

            MenuPanel(model: model)
                .environment(\.isSandboxedBuild, fixture == .connectAppStore)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                .shadow(radius: 14)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static func show(_ fixture: Fixture, in model: AppModel) {
        switch fixture {
        case .full: model.loadSample()
        case .overflow: model.loadSample(overflow: true)
        case .empty: model.loadSample(empty: true)
        case .connect, .connectAppStore: model.loadConnectScreen()
        }
    }
}
#endif
