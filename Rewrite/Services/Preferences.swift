import Foundation

enum Preferences {
    static let providerKey = "rewrite.provider"
    static let intentKey = "rewrite.intent"
    static let ollamaModelKey = "rewrite.ollamaModel"
    static let autocompleteEnabledKey = "rewrite.autocompleteEnabled"

    static func provider(from defaults: UserDefaults = .standard) -> RewriteProviderChoice {
        guard
            let rawValue = defaults.string(forKey: providerKey),
            let provider = RewriteProviderChoice(rawValue: rawValue)
        else {
            return .defaultProvider
        }
        return provider
    }

    static func intent(from defaults: UserDefaults = .standard) -> RewriteIntent {
        guard
            let rawValue = defaults.string(forKey: intentKey),
            let intent = RewriteIntent(rawValue: rawValue)
        else {
            return .defaultIntent
        }
        return intent
    }

    static func ollamaModel(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: ollamaModelKey) ?? ""
    }

    static func autocompleteEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: autocompleteEnabledKey)
    }
}
