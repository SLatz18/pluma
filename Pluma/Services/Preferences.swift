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
    static let clipboardFallbackEnabledKey = "pluma.clipboardFallbackEnabled"
    static let clipboardShortcutKeyCodeKey = "pluma.clipboardShortcut.keyCode"
    static let clipboardShortcutModifiersKey = "pluma.clipboardShortcut.modifiers"
    static let clipboardShortcutDisplayKey = "pluma.clipboardShortcut.display"
    static let readerEnabledKey = "pluma.readerEnabled"
    static let readerShortcutKeyCodeKey = "pluma.readerShortcut.keyCode"
    static let readerShortcutModifiersKey = "pluma.readerShortcut.modifiers"
    static let readerShortcutDisplayKey = "pluma.readerShortcut.display"
    static let readerVoiceIdentifierKey = "pluma.readerVoiceIdentifier"
    static let readerRateKey = "pluma.readerRate"
    static let readerDeliveryModeKey = "pluma.readerDeliveryMode"
    static let readerSpeechProviderKey = "pluma.readerSpeechProvider"
    static let openAITTSVoiceKey = "pluma.openAITTSVoice"
    static let openAITTSModelKey = "pluma.openAITTSModel"
    static let developerModeEnabledKey = "pluma.developerModeEnabled"
    static let logLevelKey = "pluma.logLevel"
    static let inlineSuggestionsKey = "pluma.inlineSuggestions"
    static let spellCorrectionEnabledKey = "pluma.spellCorrectionEnabled"
    static let spellCorrectionEngineKey = "pluma.spellCorrectionEngine"
    static let spellMemoryEnabledKey = "pluma.spellMemoryEnabled"
    static let completionPhraseWordsKey = "pluma.completion.phraseWords"
    static let completionBriefWordsKey = "pluma.completion.briefWords"
    static let completionDebounceKey = "pluma.completion.debounceMilliseconds"
    static let completionMinimumContextKey = "pluma.completion.minimumContext"
    static let conversationContextEnabledKey = "pluma.conversationContextEnabled"
    static let draftReplyEnabledKey = "pluma.draftReplyEnabled"
    static let draftShortcutKeyCodeKey = "pluma.draftShortcut.keyCode"
    static let draftShortcutModifiersKey = "pluma.draftShortcut.modifiers"
    static let draftShortcutDisplayKey = "pluma.draftShortcut.display"
    /// Opt-in: Caps Lock becomes pluma's shortcut modifier (default off).
    static let capsShortcutsEnabledKey = "pluma.capsShortcutsEnabled"
    /// When Caps shortcuts are on, include Shift in the Caps chord (⌃⌥⌘⇧).
    static let capsChordIncludesShiftKey = "pluma.capsChordIncludesShift"
    /// Lone Caps tap toggles real Caps Lock (default on).
    static let capsTapTogglesCapsLockKey = "pluma.capsTapTogglesCapsLock"
    /// Max Caps press duration still counted as a tap (seconds).
    static let capsTapThresholdKey = "pluma.capsTapThreshold"

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

    static let completionChainKey = "pluma.completionChain"
    static let cleanupChainKey = "pluma.dictationCleanupChain"

    // Both builder chains store JSON [rawValue] like the rewrite chain, so
    // order survives. A missing key means the user never touched the builder
    // and reads as the default chain — today's shipped behavior. A stored
    // empty chain is a deliberate choice and stays empty.
    static func completionChain(from defaults: UserDefaults = .standard) -> [CompletionDirective] {
        guard
            let data = defaults.data(forKey: completionChainKey),
            let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else {
            return CompletionDirective.defaultChain
        }
        return rawValues.compactMap { CompletionDirective(rawValue: $0) }
    }

    static func saveCompletionChain(
        _ chain: [CompletionDirective], to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(chain.map(\.rawValue)) else { return }
        defaults.set(data, forKey: completionChainKey)
    }

    static func cleanupChain(from defaults: UserDefaults = .standard) -> [CleanupDirective] {
        guard
            let data = defaults.data(forKey: cleanupChainKey),
            let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else {
            return CleanupDirective.defaultChain
        }
        return rawValues.compactMap { CleanupDirective(rawValue: $0) }
    }

    static func saveCleanupChain(
        _ chain: [CleanupDirective], to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(chain.map(\.rawValue)) else { return }
        defaults.set(data, forKey: cleanupChainKey)
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

    /// Default off until Caps Lock ownership is proven reliable on this Mac.
    static func capsShortcutsEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: capsShortcutsEnabledKey)
    }

    static func setCapsShortcutsEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: capsShortcutsEnabledKey)
    }

    static func capsChordIncludesShift(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: capsChordIncludesShiftKey)
    }

    static func setCapsChordIncludesShift(_ includesShift: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(includesShift, forKey: capsChordIncludesShiftKey)
    }

    /// Default on — matches CapsSpike dual-role proof. Missing key → true.
    static func capsTapTogglesCapsLock(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: capsTapTogglesCapsLockKey) == nil { return true }
        return defaults.bool(forKey: capsTapTogglesCapsLockKey)
    }

    static func setCapsTapTogglesCapsLock(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: capsTapTogglesCapsLockKey)
    }

    /// Default 0.3s. Clamped to a sane range.
    static func capsTapThreshold(from defaults: UserDefaults = .standard) -> TimeInterval {
        let raw = defaults.double(forKey: capsTapThresholdKey)
        if raw == 0 { return CapsLockStateMachine.defaultTapThreshold }
        return min(0.6, max(0.15, raw))
    }

    static func setCapsTapThreshold(_ seconds: TimeInterval, to defaults: UserDefaults = .standard) {
        defaults.set(min(0.6, max(0.15, seconds)), forKey: capsTapThresholdKey)
    }

    /// Rewrite stored Caps-chord shortcuts to match the current Caps chord setting.
    static func syncCapsChordShortcuts(to defaults: UserDefaults = .standard) {
        let includesShift = capsChordIncludesShift(from: defaults)
        let aligned = globalShortcut(from: defaults).aligningCapsChord(includesShift: includesShift)
        if aligned != globalShortcut(from: defaults) {
            saveGlobalShortcut(aligned, to: defaults)
        }
        let dictation = dictationShortcut(from: defaults).aligningCapsChord(includesShift: includesShift)
        if dictation != dictationShortcut(from: defaults) {
            saveDictationShortcut(dictation, to: defaults)
        }
        let clipboard = clipboardShortcut(from: defaults).aligningCapsChord(includesShift: includesShift)
        if clipboard != clipboardShortcut(from: defaults) {
            saveClipboardShortcut(clipboard, to: defaults)
        }
        let reader = readerShortcut(from: defaults).aligningCapsChord(includesShift: includesShift)
        if reader != readerShortcut(from: defaults) {
            saveReaderShortcut(reader, to: defaults)
        }
        let draft = draftShortcut(from: defaults).aligningCapsChord(includesShift: includesShift)
        if draft != draftShortcut(from: defaults) {
            saveDraftShortcut(draft, to: defaults)
        }
    }

    // Rides behind the screen-context switch: conversation reading is a richer
    // capture of the same surface, so it defaults on but only takes effect when
    // the user has already opted in to screen context.
    static func conversationContextEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: conversationContextEnabledKey) == nil
            ? true
            : defaults.bool(forKey: conversationContextEnabledKey)
    }

    static func setConversationContextEnabled(
        _ enabled: Bool, to defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: conversationContextEnabledKey)
    }

    /// Both toggles must agree before any conversation text is read.
    static func conversationAwarenessActive(from defaults: UserDefaults = .standard) -> Bool {
        screenContextEnabled(from: defaults) && conversationContextEnabled(from: defaults)
    }

    // On by default: the draft shortcut is separate from plain dictation, so an
    // extra registered chord costs nothing until it is held.
    static func draftReplyEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: draftReplyEnabledKey) == nil
            ? true
            : defaults.bool(forKey: draftReplyEnabledKey)
    }

    static func setDraftReplyEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: draftReplyEnabledKey)
    }

    static func draftShortcut(from defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            defaults.object(forKey: draftShortcutKeyCodeKey) != nil,
            let display = defaults.string(forKey: draftShortcutDisplayKey)
        else {
            return .draftReplyDefault
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: draftShortcutKeyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: draftShortcutModifiersKey)),
            display: display
        )
    }

    static func saveDraftShortcut(
        _ shortcut: GlobalShortcut, to defaults: UserDefaults = .standard
    ) {
        defaults.set(Int(shortcut.keyCode), forKey: draftShortcutKeyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: draftShortcutModifiersKey)
        defaults.set(shortcut.display, forKey: draftShortcutDisplayKey)
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

    // On by default: local NSSpellChecker only, and the chip already looks like
    // the system spelling popup. Unset keys read as on so existing installs
    // pick the feature up without a migration.
    static func spellCorrectionEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: spellCorrectionEnabledKey) == nil
            ? true
            : defaults.bool(forKey: spellCorrectionEnabledKey)
    }

    static func setSpellCorrectionEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: spellCorrectionEnabledKey)
    }

    // Apple Intelligence is the shipped spelling path. Developer mode can fall
    // back to the system dictionary for comparison. Unset keys read as AI.
    static func spellCorrectionEngine(from defaults: UserDefaults = .standard) -> SpellCorrectionEngine {
        guard
            let raw = defaults.string(forKey: spellCorrectionEngineKey),
            let engine = SpellCorrectionEngine(rawValue: raw)
        else {
            return .appleIntelligence
        }
        return engine
    }

    static func setSpellCorrectionEngine(
        _ engine: SpellCorrectionEngine, to defaults: UserDefaults = .standard
    ) {
        defaults.set(engine.rawValue, forKey: spellCorrectionEngineKey)
    }

    // On by default with spelling correction: remembering an accepted fix is
    // local-only and makes the next identical typo instant. Unset → on.
    static func spellMemoryEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: spellMemoryEnabledKey) == nil
            ? true
            : defaults.bool(forKey: spellMemoryEnabledKey)
    }

    static func setSpellMemoryEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: spellMemoryEnabledKey)
    }

    // Each knob falls back to the shipped value on its own, so a partially
    // written domain — or one key cleared by hand — still yields a sane whole.
    static func completionTuning(from defaults: UserDefaults = .standard) -> CompletionTuning {
        func value(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }
        let standard = CompletionTuning.standard
        return CompletionTuning(
            phraseWords: value(completionPhraseWordsKey, standard.phraseWords),
            briefWords: value(completionBriefWordsKey, standard.briefWords),
            debounceMilliseconds: value(completionDebounceKey, standard.debounceMilliseconds),
            minimumContext: value(completionMinimumContextKey, standard.minimumContext)
        ).clamped()
    }

    static func setCompletionTuning(
        _ tuning: CompletionTuning, to defaults: UserDefaults = .standard
    ) {
        let clamped = tuning.clamped()
        defaults.set(clamped.phraseWords, forKey: completionPhraseWordsKey)
        defaults.set(clamped.briefWords, forKey: completionBriefWordsKey)
        defaults.set(clamped.debounceMilliseconds, forKey: completionDebounceKey)
        defaults.set(clamped.minimumContext, forKey: completionMinimumContextKey)
    }

    static func resetCompletionTuning(to defaults: UserDefaults = .standard) {
        for key in [
            completionPhraseWordsKey, completionBriefWordsKey,
            completionDebounceKey, completionMinimumContextKey
        ] {
            defaults.removeObject(forKey: key)
        }
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

    // The clipboard fallback is opt-in: it reads the general pasteboard, which
    // can prompt under Paste from Other Apps, so it never turns itself on.
    static func clipboardFallbackEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: clipboardFallbackEnabledKey)
    }

    static func setClipboardFallbackEnabled(
        _ enabled: Bool, to defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: clipboardFallbackEnabledKey)
    }

    static func clipboardShortcut(from defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            defaults.object(forKey: clipboardShortcutKeyCodeKey) != nil,
            let display = defaults.string(forKey: clipboardShortcutDisplayKey)
        else {
            return .clipboardDefault
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: clipboardShortcutKeyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: clipboardShortcutModifiersKey)),
            display: display
        )
    }

    static func saveClipboardShortcut(
        _ shortcut: GlobalShortcut, to defaults: UserDefaults = .standard
    ) {
        defaults.set(Int(shortcut.keyCode), forKey: clipboardShortcutKeyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: clipboardShortcutModifiersKey)
        defaults.set(shortcut.display, forKey: clipboardShortcutDisplayKey)
    }

    static func readerEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: readerEnabledKey)
    }

    static func setReaderEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: readerEnabledKey)
    }

    static func readerShortcut(from defaults: UserDefaults = .standard) -> GlobalShortcut {
        guard
            defaults.object(forKey: readerShortcutKeyCodeKey) != nil,
            let display = defaults.string(forKey: readerShortcutDisplayKey)
        else {
            return .readerDefault
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: readerShortcutKeyCodeKey)),
            carbonModifiers: UInt32(defaults.integer(forKey: readerShortcutModifiersKey)),
            display: display
        )
    }

    static func saveReaderShortcut(
        _ shortcut: GlobalShortcut, to defaults: UserDefaults = .standard
    ) {
        defaults.set(Int(shortcut.keyCode), forKey: readerShortcutKeyCodeKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: readerShortcutModifiersKey)
        defaults.set(shortcut.display, forKey: readerShortcutDisplayKey)
    }

    static func readerVoiceIdentifier(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: readerVoiceIdentifierKey) ?? ""
    }

    static func setReaderVoiceIdentifier(
        _ identifier: String, to defaults: UserDefaults = .standard
    ) {
        defaults.set(identifier, forKey: readerVoiceIdentifierKey)
    }

    static let readerRateRange: ClosedRange<Double> = 0.3...0.65
    static let defaultReaderRate: Double = 0.5

    static func clampedReaderRate(_ rate: Double) -> Double {
        min(max(rate, readerRateRange.lowerBound), readerRateRange.upperBound)
    }

    static func readerRate(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: readerRateKey) != nil else { return defaultReaderRate }
        return clampedReaderRate(defaults.double(forKey: readerRateKey))
    }

    static func setReaderRate(_ rate: Double, to defaults: UserDefaults = .standard) {
        defaults.set(clampedReaderRate(rate), forKey: readerRateKey)
    }

    static func readerDeliveryMode(
        from defaults: UserDefaults = .standard
    ) -> ReaderDeliveryMode {
        guard
            let rawValue = defaults.string(forKey: readerDeliveryModeKey),
            let mode = ReaderDeliveryMode(rawValue: rawValue)
        else {
            return .verbatim
        }
        return mode
    }

    static func setReaderDeliveryMode(
        _ mode: ReaderDeliveryMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: readerDeliveryModeKey)
    }

    static func readerSpeechProvider(
        from defaults: UserDefaults = .standard
    ) -> ReaderSpeechProviderChoice {
        guard
            let rawValue = defaults.string(forKey: readerSpeechProviderKey),
            let provider = ReaderSpeechProviderChoice(rawValue: rawValue)
        else {
            return .defaultProvider
        }
        return provider
    }

    static func setReaderSpeechProvider(
        _ provider: ReaderSpeechProviderChoice,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(provider.rawValue, forKey: readerSpeechProviderKey)
    }

    static func openAITTSVoiceID(from defaults: UserDefaults = .standard) -> String {
        guard
            let rawValue = defaults.string(forKey: openAITTSVoiceKey),
            !rawValue.isEmpty
        else {
            return OpenAITTSCatalog.defaultVoiceID
        }
        return rawValue
    }

    static func setOpenAITTSVoiceID(
        _ voiceID: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(voiceID, forKey: openAITTSVoiceKey)
    }

    static func openAITTSModelID(from defaults: UserDefaults = .standard) -> String {
        guard
            let rawValue = defaults.string(forKey: openAITTSModelKey),
            !rawValue.isEmpty
        else {
            return OpenAITTSCatalog.defaultModelID
        }
        return rawValue
    }

    static func setOpenAITTSModelID(
        _ modelID: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(modelID, forKey: openAITTSModelKey)
    }

    /// Carbon refuses the same chord twice in one process, so a collision would
    /// leave one feature silently dead. `ignoring` is the slot being recorded.
    enum ShortcutOccupant: String {
        case rewrite = "Rewrite Selection"
        case dictation = "Dictation"
        case clipboard = "Clipboard Rewrite"
        case reader = "Reader"
        case draftReply = "Draft a Reply"
    }

    static func conflictMessage(
        for shortcut: GlobalShortcut,
        ignoring: ShortcutOccupant? = nil,
        from defaults: UserDefaults = .standard
    ) -> String? {
        let occupants: [(ShortcutOccupant, GlobalShortcut)] = [
            (.rewrite, globalShortcut(from: defaults)),
            (.dictation, dictationShortcut(from: defaults)),
            (.clipboard, clipboardShortcut(from: defaults)),
            (.reader, readerShortcut(from: defaults)),
            (.draftReply, draftShortcut(from: defaults))
        ]
        for (occupant, existing) in occupants {
            if occupant == ignoring { continue }
            if shortcut.conflicts(with: existing) {
                return "\(shortcut.display) is already used by \(occupant.rawValue)."
            }
        }
        return nil
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
