import Foundation
import Security

// API keys belong in the keychain, not in UserDefaults where any process that
// can read a plist can read the key.
//
// TODO(Developer ID): switch this store to the data protection keychain
// (`kSecUseDataProtectionKeychain` + `keychain-access-groups`). Self-signed
// builds cannot carry that entitlement (errSecMissingEntitlement -34018), so
// we stay on the file-based keychain and accept ACL prompts when the signing
// leaf changes. Once Pluma has a Developer ID / team, migrate — see CLAUDE.md.
enum KeychainStore {
    private static let service = "com.scottlatz.Pluma"
    // Keys saved before the pluma rename sit under the old service name. Without
    // this the rename silently loses an already-entered API key.
    private static let legacyService = "com.scottlatz.Rewrite"

    // Answers "is something stored" from the item's attributes without reading
    // its data. Reading the secret is a separate authorization, and asking a
    // yes/no question shouldn't require it.
    static func hasValue(for account: String) -> Bool {
        migrateLegacyItemIfNeeded(account: account)
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func string(for account: String) -> String? {
        migrateLegacyItemIfNeeded(account: account)
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

        // Delete then add rather than SecItemUpdate. An update leaves the item's
        // access control list as it was born, so a key first saved under a
        // different signing identity keeps asking the user to approve every read.
        // Re-creating the item rebinds the ACL to the identity running now.
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var insert = baseQuery(account: account)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus != errSecSuccess {
            DebugLog.log("keychain add failed for \(account): \(addStatus)", at: .quiet)
        }
    }

    // Clears the legacy item too, otherwise the next read migrates the old value
    // back and the key the user just removed reappears.
    static func remove(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        SecItemDelete(baseQuery(account: account, service: legacyService) as CFDictionary)
    }

    // Copies rather than moves: leaving the old item alone keeps a downgrade to a
    // pre-rename build working, and matches how the UserDefaults migration behaves.
    private static func migrateLegacyItemIfNeeded(account: String) {
        var probe = baseQuery(account: account)
        probe[kSecReturnAttributes as String] = true
        probe[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(probe as CFDictionary, nil) == errSecItemNotFound else { return }

        var legacy = baseQuery(account: account, service: legacyService)
        legacy[kSecReturnData as String] = true
        legacy[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(legacy as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return }

        var insert = baseQuery(account: account)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess {
            DebugLog.log("keychain migrate failed for \(account): \(status)")
        }
    }

    private static func baseQuery(account: String, service: String = KeychainStore.service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
