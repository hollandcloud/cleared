import SwiftUI

/// Cleared's palette. Amber is the accent because amber is what a held
/// deployment is: not broken, just not moving.
enum Theme {
    static let hold = Color(red: 0.85, green: 0.62, blue: 0.16)
    static let go = Color(red: 0.20, green: 0.70, blue: 0.48)
    static let stop = Color(red: 0.85, green: 0.36, blue: 0.30)
    static let muted = Color.secondary

    static let rowHeight: CGFloat = 30
    static let panelWidth: CGFloat = 372
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
