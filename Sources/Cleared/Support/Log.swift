import os

/// Unified-log channels, readable with
/// `log stream --predicate 'subsystem == "net.hlnd.Cleared"' --level debug`.
///
/// The token never goes near these. Repository names are marked private so
/// they are redacted in any log collected off the machine.
enum Log {
    private static let subsystem = "net.hlnd.Cleared"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let poll = Logger(subsystem: subsystem, category: "poll")
    static let github = Logger(subsystem: subsystem, category: "github")
}
