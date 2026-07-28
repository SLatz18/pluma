import Foundation

enum Preferences {
    static let providerKey = "rewrite.provider"
    static let intentKey = "rewrite.intent"
    static let ollamaModelKey = "rewrite.ollamaModel"
    static let autocompleteEnabledKey = "rewrite.autocompleteEnabled"
    static let shortcutKeyCodeKey = "rewrite.shortcut.keyCode"
    static let shortcutModifiersKey = "rewrite.shortcut.modifiers"
    static let shortcutDisplayKey = "rewrite.shortcut.display"

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

    static func globalShortcut(from defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            defaults.object(forKey: shortcutKeyCodeKey) != nil,
            let display = defaults.string(forKey: shortcutDisplayKey)
        else {
            return .default
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: shortcutKeyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: shortcutModifiersKey)),
            display: display
        )
    }

    static func saveGlobalShortcut(_ shortcut: GlobalShortcut, to defaults: UserDefaults = .standard) {
        defaults.set(Int(shortcut.keyCode), forKey: shortcutKeyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: shortcutModifiersKey)
        defaults.set(shortcut.display, forKey: shortcutDisplayKey)
    }
}
