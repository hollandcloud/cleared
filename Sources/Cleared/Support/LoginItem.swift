import Foundation
import ServiceManagement

/// Launch at login. A hold notifier that only runs when someone remembers to
/// open it has the same blind spot as the browser tab it replaces.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS registers the app by where it lives, so a copy run straight out
    /// of a build folder would register a path the next build deletes.
    static var isInstalled: Bool {
#if DEBUG
        // Store screenshots are taken from a build folder but have to show
        // what an installed copy shows.
        if CommandLine.arguments.contains("--bare") { return true }
#endif
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
