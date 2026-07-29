import Foundation

enum OpenAIKey {
    private static let account = "openai.apiKey"

    static var current: String? { KeychainStore.string(for: account) }
    static var isPresent: Bool { current != nil }

    static func save(_ value: String) { KeychainStore.save(value, for: account) }
    static func clear() { KeychainStore.remove(account: account) }

    // Enough to show which key is stored without showing the key.
    static func redactedSummary() -> String? {
        guard let key = current, key.count > 8 else { return nil }
        return "\(key.prefix(6))…\(key.suffix(4))"
    }
}
