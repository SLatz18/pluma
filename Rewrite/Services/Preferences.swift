import Foundation

enum Preferences {
    static let providerKey = "rewrite.provider"
    static let intentKey = "rewrite.intent"
    static let ollamaModelKey = "rewrite.ollamaModel"
    static let styleProfileKey = "rewrite.styleProfile"

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

    /// Selected style profile ID; empty means "No Style".
    static func styleProfileID(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: styleProfileKey) ?? StyleProfile.none.id
    }

    static func styleProfile(from defaults: UserDefaults = .standard) -> StyleProfile {
        StyleProfileStore.profile(id: styleProfileID(from: defaults), defaults: defaults)
    }
}
