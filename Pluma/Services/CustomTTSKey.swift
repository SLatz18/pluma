import Foundation

/// API key for the custom OpenAI-compatible speech endpoint. Separate from
/// `OpenAIKey` so removing one credential never breaks the other provider.
enum CustomTTSKey {
    private static let account = "customTTS.apiKey"

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
    // single authorization covers the whole session. Same rationale as
    // `OpenAIKey.secret`; see the notes there and in KeychainStore.
    private static let secret = CustomTTSSecretCache()

    static var current: String? {
        secret.value { KeychainStore.string(for: account) }
    }

    /// Gateways that rotate keys (common for corporate proxies) leave stale
    /// credentials behind silently; the save date powers an "is this key old?"
    /// hint when the endpoint starts rejecting requests.
    @MainActor
    static func save(_ value: String, to defaults: UserDefaults = .standard) throws {
        defer {
            cachedPresence = nil
            secret.invalidate()
        }
        try KeychainStore.save(value, for: account)
        Preferences.setCustomTTSKeySavedAt(Date(), to: defaults)
    }

    @MainActor
    static func clear(from defaults: UserDefaults = .standard) throws {
        defer {
            cachedPresence = nil
            secret.invalidate()
        }
        try KeychainStore.remove(account: account)
        Preferences.setCustomTTSKeySavedAt(nil, to: defaults)
    }
}

// The outer optional records whether the keychain has been consulted; the inner
// one is the answer it gave, so a genuinely absent key isn't re-read every time.
private final class CustomTTSSecretCache: @unchecked Sendable {
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
