import Foundation

enum Preferences {
    static let providerKey = "rewrite.provider"
    static let intentKey = "rewrite.intent"
    static let ollamaModelKey = "rewrite.ollamaModel"
    static let autocompleteEnabledKey = "rewrite.autocompleteEnabled"
    static let screenContextEnabledKey = "rewrite.screenContextEnabled"
    static let memoryEnabledKey = "rewrite.memoryEnabled"
    static let shortcutKeyCodeKey = "rewrite.shortcut.keyCode"
    static let shortcutModifiersKey = "rewrite.shortcut.modifiers"
    static let shortcutDisplayKey = "rewrite.shortcut.display"
    static let dictationEnabledKey = "rewrite.dictationEnabled"
    static let dictationCleanupEnabledKey = "rewrite.dictationCleanupEnabled"
    static let dictationShortcutKeyCodeKey = "rewrite.dictationShortcut.keyCode"
    static let dictationShortcutModifiersKey = "rewrite.dictationShortcut.modifiers"
    static let dictationShortcutDisplayKey = "rewrite.dictationShortcut.display"
    static let dictationProviderKey = "rewrite.dictationProvider"
    static let cleanupProviderKey = "rewrite.dictationCleanupProvider"
    static let openAICleanupModelKey = "rewrite.openAICleanupModel"

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

    static let chainKey = "rewrite.chain"

    // The pipeline is stored as JSON [rawValue] so step order survives. A
    // missing chain seeds itself from the old single-intent preference, so an
    // upgrade keeps the user's selection as a one-step pipeline.
    static func chain(from defaults: UserDefaults = .standard) -> [RewriteIntent] {
        if let data = defaults.data(forKey: chainKey),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            return rawValues.compactMap { RewriteIntent(rawValue: $0) }
        }
        let seeded = [intent(from: defaults)]
        saveChain(seeded, to: defaults)
        return seeded
    }

    static func saveChain(_ chain: [RewriteIntent], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(chain.map(\.rawValue)) else { return }
        defaults.set(data, forKey: chainKey)
    }

    static func ollamaModel(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: ollamaModelKey) ?? ""
    }

    static func autocompleteEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: autocompleteEnabledKey)
    }

    static func screenContextEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: screenContextEnabledKey)
    }

    static func memoryEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: memoryEnabledKey)
    }

    static func dictationEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: dictationEnabledKey)
    }

    // Cleanup is on unless the user turned it off, so register a default rather
    // than relying on bool(forKey:) returning false for an absent key.
    static func dictationCleanupEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: dictationCleanupEnabledKey) != nil else { return true }
        return defaults.bool(forKey: dictationCleanupEnabledKey)
    }

    static func dictationProvider(
        from defaults: UserDefaults = .standard
    ) -> DictationProviderChoice {
        guard
            let rawValue = defaults.string(forKey: dictationProviderKey),
            let provider = DictationProviderChoice(rawValue: rawValue)
        else {
            return .defaultProvider
        }
        return provider
    }

    static func cleanupProvider(
        from defaults: UserDefaults = .standard
    ) -> CleanupProviderChoice {
        guard
            let rawValue = defaults.string(forKey: cleanupProviderKey),
            let provider = CleanupProviderChoice(rawValue: rawValue)
        else {
            return .defaultProvider
        }
        return provider
    }

    static func openAICleanupModel(from defaults: UserDefaults = .standard) -> OpenAIChatModel {
        guard
            let rawValue = defaults.string(forKey: openAICleanupModelKey),
            let model = OpenAIChatModel(rawValue: rawValue)
        else {
            return .defaultModel
        }
        return model
    }

    static func dictationShortcut(from defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            defaults.object(forKey: dictationShortcutKeyCodeKey) != nil,
            let display = defaults.string(forKey: dictationShortcutDisplayKey)
        else {
            return .dictationDefault
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: dictationShortcutKeyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: dictationShortcutModifiersKey)),
            display: display
        )
    }

    static func saveDictationShortcut(
        _ shortcut: GlobalShortcut, to defaults: UserDefaults = .standard
    ) {
        defaults.set(Int(shortcut.keyCode), forKey: dictationShortcutKeyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: dictationShortcutModifiersKey)
        defaults.set(shortcut.display, forKey: dictationShortcutDisplayKey)
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
