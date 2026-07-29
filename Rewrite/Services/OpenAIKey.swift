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

    // Held in memory for the life of the process after the first read. These are
    // ad-hoc signed builds, so every rebuild is a new code identity and the
    // keychain grant from the previous build no longer applies — reading the
    // secret per request meant a fresh authorization prompt per request.
    private static let secret = SecretCache()

    static var current: String? {
        secret.value { KeychainStore.string(for: account) }
    }

    @MainActor
    static func save(_ value: String) {
        KeychainStore.save(value, for: account)
        cachedPresence = nil
        secret.invalidate()
    }

    @MainActor
    static func clear() {
        KeychainStore.remove(account: account)
        cachedPresence = nil
        secret.invalidate()
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
