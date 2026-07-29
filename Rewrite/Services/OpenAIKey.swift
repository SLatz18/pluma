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

    // The secret itself, read fresh and only when a request is actually going out.
    static var current: String? { KeychainStore.string(for: account) }

    @MainActor
    static func save(_ value: String) {
        KeychainStore.save(value, for: account)
        cachedPresence = nil
    }

    @MainActor
    static func clear() {
        KeychainStore.remove(account: account)
        cachedPresence = nil
    }
}
