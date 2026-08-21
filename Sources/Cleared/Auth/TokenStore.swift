import Foundation

/// Owns the GitHub token: reads it from the Keychain, offers a one-shot import
/// from the `gh` CLI, and guarantees the raw value never reaches a log or the UI.
struct TokenStore: Sendable {
    private static let account = "github-token"

    /// The token, or nil if Cleared has not been connected yet.
    static func current() -> String? {
        guard let token = Keychain.get(account: account), !token.isEmpty else { return nil }
        return token
    }

    static func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TokenError.empty }
        try Keychain.set(trimmed, account: account)
    }

    static func clear() {
        Keychain.delete(account: account)
    }

    /// Distinguishes "never connected" from "connected, but this build cannot
    /// read the saved token" so the UI can say which one happened.
    static func status() -> Keychain.Lookup {
        Keychain.lookup(account: account)
    }

    /// Everything Cleared ever shows about a token. Never the token.
    static func fingerprint(_ token: String) -> String {
        let prefix = token.prefix(4)
        return "\(prefix)…\(token.suffix(4)) · \(token.count) chars"
    }

    enum TokenError: Error, LocalizedError {
        case empty
        case ghNotFound
        case ghFailed(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "That token is empty."
            case .ghNotFound:
                return "Couldn't find the gh CLI. Install it, or paste a token instead."
            case .ghFailed(let detail):
                return "gh couldn't return a token. \(detail)"
            }
        }
    }
}

/// Imports the token from an existing `gh auth login`, so connecting Cleared is
/// one click for anyone who already uses the GitHub CLI.
enum GHCLIImporter {
    private static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    static func locate() -> URL? {
        candidatePaths.lazy
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
            .first
            .map { URL(fileURLWithPath: $0) }
    }

    static func importToken() throws -> String {
        guard let gh = locate() else { throw TokenStore.TokenError.ghNotFound }

        let process = Process()
        process.executableURL = gh
        process.arguments = ["auth", "token"]
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TokenStore.TokenError.ghFailed(detail.isEmpty ? "Try `gh auth login` first." : detail)
        }

        let token = String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TokenStore.TokenError.empty }
        return token
    }
}
