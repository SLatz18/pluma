import Carbon.HIToolbox
import Foundation

enum Preferences {
    static let providerKey = "pluma.provider"
    static let intentKey = "pluma.intent"
    static let ollamaModelKey = "pluma.ollamaModel"
    static let autocompleteEnabledKey = "pluma.autocompleteEnabled"
    static let screenContextEnabledKey = "pluma.screenContextEnabled"
    static let memoryEnabledKey = "pluma.memoryEnabled"
    static let shortcutKeyCodeKey = "pluma.shortcut.keyCode"
    static let shortcutModifiersKey = "pluma.shortcut.modifiers"
    static let shortcutDisplayKey = "pluma.shortcut.display"
    static let dictationEnabledKey = "pluma.dictationEnabled"
    static let dictationCleanupEnabledKey = "pluma.dictationCleanupEnabled"
    static let dictationShortcutKeyCodeKey = "pluma.dictationShortcut.keyCode"
    static let dictationShortcutModifiersKey = "pluma.dictationShortcut.modifiers"
    static let dictationShortcutDisplayKey = "pluma.dictationShortcut.display"
    static let dictationProviderKey = "pluma.dictationProvider"
    static let cleanupProviderKey = "pluma.dictationCleanupProvider"
    static let openAICleanupModelKey = "pluma.openAICleanupModel"
    static let developerModeEnabledKey = "pluma.developerModeEnabled"
    static let logLevelKey = "pluma.logLevel"
    static let inlineSuggestionsKey = "pluma.inlineSuggestions"

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

    static let chainKey = "pluma.chain"

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

    // Off by default: drawing the suggestion into the writer's own line needs the
    // exact glyph origin, baseline, and font of the field it is landing in, and
    // only well-behaved AppKit apps report all three. Everywhere else it is
    // approximations stacked on approximations and it shows. The chip below the
    // caret only needs to know roughly where the caret is, which every app
    // manages, so that is what ships.
    static func inlineSuggestions(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: inlineSuggestionsKey)
    }

    static func setInlineSuggestions(_ inline: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(inline, forKey: inlineSuggestionsKey)
    }

    // Developer mode is off until the cheat code unlocks it, so a missing key
    // reading false is exactly right.
    static func developerModeEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: developerModeEnabledKey)
    }

    static func setDeveloperModeEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: developerModeEnabledKey)
    }

    static func logLevel(from defaults: UserDefaults = .standard) -> DebugLog.Level {
        guard
            defaults.object(forKey: logLevelKey) != nil,
            let level = DebugLog.Level(rawValue: defaults.integer(forKey: logLevelKey))
        else {
            return .normal
        }
        return level
    }

    static func setLogLevel(_ level: DebugLog.Level, to defaults: UserDefaults = .standard) {
        defaults.set(level.rawValue, forKey: logLevelKey)
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

    static let shortcutsVersionKey = "pluma.shortcutsVersion"
    private static let legacyKeyPrefix = "rewrite."
    private static let keyPrefix = "pluma."

    // 2026-07 factory chords moved from ⇧⌘E / ⇪R to ⇪E / ⇪Space. Stored
    // values only exist after a recording, so users still on the old factory
    // chords get moved forward; anyone who recorded something custom is left
    // exactly where they were.
    //
    // Also copies rewrite.* UserDefaults into pluma.* once after the rename.
    static func migrateShortcutDefaultsIfNeeded(from defaults: UserDefaults = .standard) {
        migrateLegacyPreferenceKeysIfNeeded(from: defaults)

        guard defaults.integer(forKey: shortcutsVersionKey) < 1 else { return }

        let storedRewrite = globalShortcut(from: defaults)
        if storedRewrite.keyCode == UInt32(kVK_ANSI_E),
           storedRewrite.carbonModifiers == UInt32(cmdKey | shiftKey) {
            saveGlobalShortcut(.default, to: defaults)
        }

        let storedDictation = dictationShortcut(from: defaults)
        if storedDictation.keyCode == UInt32(kVK_ANSI_R),
           storedDictation.carbonModifiers == UInt32(controlKey | optionKey | cmdKey) {
            saveDictationShortcut(.dictationDefault, to: defaults)
        }

        defaults.set(1, forKey: shortcutsVersionKey)
    }

    private static let preferenceMigrationKey = "pluma.didMigrateRewriteKeys"

    private static func migrateLegacyPreferenceKeysIfNeeded(from defaults: UserDefaults) {
        guard !defaults.bool(forKey: preferenceMigrationKey) else { return }
        let legacyKeys = [
            "provider", "intent", "ollamaModel", "autocompleteEnabled",
            "screenContextEnabled", "memoryEnabled", "shortcut.keyCode",
            "shortcut.modifiers", "shortcut.display", "dictationEnabled",
            "dictationCleanupEnabled", "dictationShortcut.keyCode",
            "dictationShortcut.modifiers", "dictationShortcut.display",
            "dictationProvider", "dictationCleanupProvider", "openAICleanupModel",
            "chain", "shortcutsVersion"
        ]
        for suffix in legacyKeys {
            let legacy = legacyKeyPrefix + suffix
            let modern = keyPrefix + suffix
            if defaults.object(forKey: modern) == nil, let value = defaults.object(forKey: legacy) {
                defaults.set(value, forKey: modern)
            }
        }
        defaults.set(true, forKey: preferenceMigrationKey)
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
