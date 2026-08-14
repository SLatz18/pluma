import Foundation

enum OpenAIKey {
    private static let account = "openai.apiKey"

    // SwiftUI re-evaluates a view body on every state change — a keystroke, a
    // toggle, a window resize — so anything a body asks about the key would
    // otherwise hit the keychain hundreds of times. Presence is read from item
    // attributes rather than data, and then cached until it changes.
    @MainActor private static var cachedPresence: Bool?

    @MainActor
    static var isPresent: Bool {
        if let cachedPresence { return cachedPresence }
        let present = KeychainStore.hasValue(for: account)
        cachedPresence = present
        return present
    }

    // Held in memory for the life of the process after the first read so a
    // single authorization covers the whole session. With the Local Self-Signed
    // identity, rebuilds keep the same designated requirement — prompts only
    // reappear if the signing leaf changes. Drop this cache (or keep it as a
    // pure perf win) when KeychainStore moves to the data protection keychain;
    // see the TODO there and CLAUDE.md.
    private static let secret = SecretCache()

    static var current: String? {
        secret.value { KeychainStore.string(for: account) }
    }

    @MainActor
    static func save(_ value: String) throws {
        defer {
            cachedPresence = nil
            secret.invalidate()
        }
        try KeychainStore.save(value, for: account)
        // Custom gateways rotate keys (commonly every ~28 days); the save date
        // powers an "is this key old?" hint when the endpoint starts rejecting.
        Preferences.setOpenAIKeySavedAt(Date())
    }

    @MainActor
    static func clear() throws {
        defer {
            cachedPresence = nil
            secret.invalidate()
        }
        try KeychainStore.remove(account: account)
        Preferences.setOpenAIKeySavedAt(nil)
    }

    /// One-time migration from the short-lived separate custom-TTS credential:
    /// adopt its secret as THE cloud key when no key is stored yet, then drop
    /// the legacy item either way.
    @MainActor
    static func migrateFromLegacyCustomTTSKeyIfNeeded() {
        let legacyAccount = "customTTS.apiKey"
        guard KeychainStore.hasValue(for: legacyAccount) else { return }
        if !isPresent, let value = KeychainStore.string(for: legacyAccount) {
            try? save(value)
        }
        try? KeychainStore.remove(account: legacyAccount)
    }
}

// The outer optional records whether the keychain has been consulted; the inner
// one is the answer it gave, so a genuinely absent key isn't re-read every time.
private final class SecretCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: String??

    func value(_ load: () -> String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = load()
        cached = loaded
        return loaded
    }

    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}
