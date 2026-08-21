import SwiftUI

/// Cleared's palette. Amber is the accent because amber is what a held
/// deployment is: not broken, just not moving.
enum Theme {
    static let hold = Color(red: 0.85, green: 0.62, blue: 0.16)
    static let go = Color(red: 0.20, green: 0.70, blue: 0.48)
    static let stop = Color(red: 0.85, green: 0.36, blue: 0.30)
    static let muted = Color.secondary

    static let panelWidth: CGFloat = 420

    /// Room for roughly a dozen rows before the queue starts scrolling, but
    /// never more than two-thirds of the screen — a menu bar panel that runs
    /// from the menu bar to the Dock reads as a window, not a menu.
    static var maxQueueHeight: CGFloat {
        let usable = NSScreen.main?.visibleFrame.height ?? 900
        return min(560, max(220, usable * 0.66))
    }
}

extension Date {
    /// "6m", "3h", "2d" — how long something has been sitting.
    var heldDuration: String {
        let seconds = max(0, Date().timeIntervalSince(self))
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}

/// Reports the natural height of the queue so the panel can size itself to its
/// contents. A ScrollView has no intrinsic height of its own — left alone it
/// collapses to a single row inside a MenuBarExtra window.
struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func measureHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
    }
}
