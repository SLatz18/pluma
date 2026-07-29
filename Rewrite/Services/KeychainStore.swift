import Foundation
import Security

// API keys belong in the keychain, not in UserDefaults where any process that
// can read a plist can read the key.
enum KeychainStore {
    private static let service = "com.scottlatz.Rewrite"

    // Answers "is something stored" from the item's attributes without reading
    // its data. Reading the secret is a separate authorization, and asking a
    // yes/no question shouldn't require it.
    static func hasValue(for account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else { return nil }
        return value
    }

    static func save(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(account: account)
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }

        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                DebugLog.log("keychain add failed for \(account): \(addStatus)")
            }
        } else if status != errSecSuccess {
            DebugLog.log("keychain update failed for \(account): \(status)")
        }
    }

    static func remove(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
