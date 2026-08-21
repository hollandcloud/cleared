import Foundation
import Security

/// Minimal Keychain wrapper. The GitHub token lives here and nowhere else —
/// never in UserDefaults, never on disk in plaintext, never in a log line.
enum Keychain {
    enum Failure: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return message ?? "Keychain error \(status)"
            }
        }
    }

    private static let service = "net.hlnd.Cleared"

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.unexpectedStatus(addStatus) }
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    /// Why a read came back empty. "Nothing saved" and "saved but unreadable"
    /// look identical to a caller that only gets an optional, and they need
    /// completely different messages: one asks you to connect, the other tells
    /// you the system denied access.
    enum Lookup {
        case found(String)
        case notFound
        case denied(OSStatus)
    }

    static func lookup(account: String) -> Lookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                return .notFound
            }
            return .found(string)
        case errSecItemNotFound:
            return .notFound
        default:
            // errSecAuthFailed / errSecInteractionNotAllowed land here. The most
            // common cause is a rebuild: an ad-hoc signature changes identity,
            // so the ACL on the existing item no longer matches this binary.
            return .denied(status)
        }
    }

    static func get(account: String) -> String? {
        if case .found(let value) = lookup(account: account) { return value }
        return nil
    }

    static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
