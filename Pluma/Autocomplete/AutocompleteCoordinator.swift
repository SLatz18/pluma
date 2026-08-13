import AppKit
import ApplicationServices

enum AutocompleteActivity: Equatable {
    case off
    case needsPermission
    case watching
    case suggesting
}

@MainActor
final class AutocompleteCoordinator: ObservableObject {
    @Published private(set) var activity: AutocompleteActivity = .off
    @Published private(set) var isPermissionGranted: Bool

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Preferences.autocompleteEnabledKey)
            if isEnabled {
                startIfPossible()
            } else {
                stop()
            }
        }
    }

    @Published var screenContextEnabled: Bool {
        didSet {
            defaults.set(screenContextEnabled, forKey: Preferences.screenContextEnabledKey)
            if screenContextEnabled && !screenContext.isPermitted {
                requestScreenContextPermission()
            }
        }
    }

    @Published var memoryEnabled: Bool {
        didSet {
            defaults.set(memoryEnabled, forKey: Preferences.memoryEnabledKey)
        }
    }

    @Published var tuning: CompletionTuning {
        didSet {
            guard tuning != oldValue else { return }
            Preferences.setCompletionTuning(tuning, to: defaults)
        }
    }

    @Published var inlineSuggestions: Bool {
        didSet {
            guard inlineSuggestions != oldValue else { return }
            Preferences.setInlineSuggestions(inlineSuggestions, to: defaults)
            // The two looks are different windows' worth of layout; whatever is
            // on screen was drawn for the old one.
            dismissSuggestion()
        }
    }

    @Published var spellCorrectionEnabled: Bool {
        didSet {
            guard spellCorrectionEnabled != oldValue else { return }
            Preferences.setSpellCorrectionEnabled(spellCorrectionEnabled, to: defaults)
            if !spellCorrectionEnabled, activeCorrection != nil {
                dismissSuggestion()
            }
        }
    }

    @Published var spellCorrectionEngine: SpellCorrectionEngine {
        didSet {
            guard spellCorrectionEngine != oldValue else { return }
            Preferences.setSpellCorrectionEngine(spellCorrectionEngine, to: defaults)
            if activeCorrection != nil {
                dismissSuggestion()
            }
        }
    }

    @Published var spellMemoryEnabled: Bool {
        didSet {
            guard spellMemoryEnabled != oldValue else { return }
            Preferences.setSpellMemoryEnabled(spellMemoryEnabled, to: defaults)
        }
    }

    @Published private(set) var directiveChain: [CompletionDirective]

    @Published private(set) var isScreenContextPermitted: Bool
    @Published private(set) var memoryEntryCount: Int
    @Published private(set) var spellMemoryEntryCount: Int

    private let defaults: UserDefaults
    private let tracker = FocusedFieldTracker()
    private let overlay: SuggestionOverlayController
    private let permission = AccessibilityPermission.shared
    private let screenContext = ScreenContextProvider.shared
    private let memory = MemoryStore.shared
    private let spellMemory = SpellMemoryStore.shared

    private var debounceTask: Task<Void, Never>?
    private var completionInFlight = false
    private var appleSpellTask: Task<Void, Never>?
    private var latestSnapshot: FocusedFieldSnapshot?
    private var activeSuggestion: CompletionSuggestion?
    private var activeCorrection: SpellCorrectionOffer?
    private var activeElement: AXUIElement?
    private var lastSnapshotPrefix: String?
    private var ghostEligibility = GhostTextEligibility.unknown
    private var acceptedFromCurrentSuggestion = ""
    private var activeSuggestionTopLeftY: CGFloat?
    private var isAcceptingSuggestion = false
    private var requestSequence = 0
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?


    init(defaults: UserDefaults = .standard, overlay: SuggestionOverlayController = SuggestionOverlayController()) {
        self.defaults = defaults
        self.overlay = overlay
        isEnabled = Preferences.autocompleteEnabled(from: defaults)
        screenContextEnabled = Preferences.screenContextEnabled(from: defaults)
        memoryEnabled = Preferences.memoryEnabled(from: defaults)
        inlineSuggestions = Preferences.inlineSuggestions(from: defaults)
        spellCorrectionEnabled = Preferences.spellCorrectionEnabled(from: defaults)
        spellCorrectionEngine = Preferences.spellCorrectionEngine(from: defaults)
        spellMemoryEnabled = Preferences.spellMemoryEnabled(from: defaults)
        directiveChain = Preferences.completionChain(from: defaults)
        tuning = Preferences.completionTuning(from: defaults)
        isPermissionGranted = permission.isTrusted
        isScreenContextPermitted = screenContext.isPermitted
        memoryEntryCount = memory.count
        spellMemoryEntryCount = spellMemory.count
        DebugLog.truncate()
        DebugLog.log("coordinator init trusted=\(permission.isTrusted) enabled=\(isEnabled) screenCtx=\(screenContextEnabled) screenPermitted=\(isScreenContextPermitted)", at: .quiet)

        screenContext.onChange = { [weak self] permitted in
            Task { @MainActor [weak self] in
                self?.isScreenContextPermitted = permitted
            }
        }
        screenContext.startMonitoring()

        permission.onChange = { [weak self] trusted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isPermissionGranted = trusted
                if trusted && isEnabled {
                    startIfPossible()
                } else if !trusted {
                    stop()
                    updateActivity()
                }
            }
        }

        tracker.onSnapshot = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.handleSnapshot(snapshot)
            }
        }

        if isEnabled {
            startIfPossible()
        } else {
            updateActivity()
        }
        permission.startMonitoring()
    }

    func requestPermission() {
        permission.requestPrompt()
        // The prompt only appears once; if the user previously dismissed it,
        // the settings pane is the only way back, so open it too.
        permission.openSystemSettings()
        isPermissionGranted = permission.isTrusted
        updateActivity()
    }

    func requestScreenContextPermission() {
        screenContext.requestPermission()
        isScreenContextPermitted = screenContext.isPermitted
    }

    func clearMemory() {
        memory.clear()
        memoryEntryCount = 0
    }

    func clearSpellMemory() {
        spellMemory.clear()
        spellMemoryEntryCount = 0
    }

    private func startIfPossible() {
        guard permission.isTrusted else {
            DebugLog.log("start blocked: not trusted", at: .quiet)
            updateActivity()
            return
        }
        DebugLog.log("tracker + event tap starting")
        tracker.start()
        installEventTapIfNeeded()
        updateActivity()
    }

    private func stop() {
        debounceTask?.cancel()
        appleSpellTask?.cancel()
        tracker.stop()
        dismissSuggestion()
        removeEventTap()
        updateActivity()
    }

    private func updateActivity() {
        if !isEnabled {
            activity = .off
        } else if !permission.isTrusted {
            activity = .needsPermission
        } else if activeSuggestion != nil || activeCorrection != nil {
            activity = .suggesting
        } else {
            activity = .watching
        }
    }

    private func handleSnapshot(_ snapshot: FocusedFieldSnapshot?) {
        // Accepting through AX can emit a transient empty/focus snapshot before
        // the field reports its final value. That is our own edit, not new user
        // input; handling it would hide and recreate the pill mid-accept.
        guard !isAcceptingSuggestion else { return }

        guard let snapshot else {
            latestSnapshot = nil
            debounceTask?.cancel()
            appleSpellTask?.cancel()
            dismissSuggestion()
            lastSnapshotPrefix = nil
            updateActivity()
            return
        }

        let prefix = snapshot.textBeforeCaret
        latestSnapshot = snapshot
        // Decided here rather than at draw time: the field's whole text is in
        // hand now, and re-reading it on every repaint would cost an AX round
        // trip per keystroke.
        ghostEligibility = snapshot.ghostEligibility

        if activeSuggestion != nil {
            handleTypedProgress(prefix: prefix)
            lastSnapshotPrefix = prefix
            return
        }

        if let correction = activeCorrection {
            // Still the same finished misspelling — keep the chip. Any other
            // edit clears it so a fresh correction or model pass can run.
            if spellCorrectionEnabled,
               let candidate = spellCorrectionCandidate(for: prefix),
               candidate.word == correction.misspelled,
               candidate.range.location == correction.wordLocation,
               candidate.range.length == correction.wordLength {
                lastSnapshotPrefix = prefix
                return
            }
            dismissSuggestion()
        }

        guard prefix != lastSnapshotPrefix else { return }
        lastSnapshotPrefix = prefix
        DebugLog.log("snapshot len=\(prefix.count) caret=\(snapshot.caretLocation)", at: .verbose)

        if presentSpellCorrectionIfNeeded(for: snapshot) {
            return
        }

        // Once the model is working, ordinary continued typing should not kill
        // it. The result is rebased against those extra characters below.
        // Focus loss and stop() still cancel the task immediately.
        guard !completionInFlight else {
            DebugLog.log("typing advanced while completion is in flight", at: .verbose)
            return
        }

        scheduleCompletion(for: snapshot)
    }

    // Finished misspellings beat continuation suggestions: the writer already
    // put the wrong word down, and fixing it is more urgent than guessing what
    // comes next. Corrections always wear the chip — ghost text appends, and a
    // replace-in-place must not pose as grey continuation.
    private func presentSpellCorrectionIfNeeded(for snapshot: FocusedFieldSnapshot) -> Bool {
        guard spellCorrectionEnabled else { return false }
        guard let candidate = spellCorrectionCandidate(for: snapshot.textBeforeCaret) else {
            appleSpellTask?.cancel()
            return false
        }

        // Learned fixes beat dictionary and Apple Intelligence — they are the
        // writer's own accepted answers for this exact misspelling. Still apply
        // the grammar gate so a remembered "separation" is not offered after
        // "will carefully".
        if spellMemoryEnabled,
           let learned = spellMemory.lookup(candidate.word),
           SpellCorrection.fitsGrammatically(
               learned,
               after: SpellCorrection.precedingText(
                   inPrefix: snapshot.textBeforeCaret, wordRange: candidate.range
               )
           ),
           let offer = SpellCorrection.offer(
               misspelled: candidate.word, range: candidate.range, replacement: learned
           ) {
            presentCorrection(offer, element: snapshot.element, caret: snapshot.caret)
            DebugLog.log("spell memory hit: \(candidate.word) -> \(learned)")
            return true
        }

        switch spellCorrectionEngine {
        case .dictionary:
            guard let offer = dictionarySpellCorrectionOffer(for: snapshot.textBeforeCaret) else {
                return false
            }
            presentCorrection(offer, element: snapshot.element, caret: snapshot.caret)
            return true
        case .appleIntelligence:
            scheduleAppleSpellCorrection(for: snapshot)
            return true
        }
    }

    private func spellCorrectionCandidate(
        for prefix: String
    ) -> (word: String, range: NSRange)? {
        SpellCorrection.candidateWordRange(
            inPrefix: prefix,
            allowMidWord: spellCorrectionEngine == .appleIntelligence,
            isMisspelled: { [self] word in !isCompleteWord(word) }
        )
    }

    private func dictionarySpellCorrectionOffer(for prefix: String) -> SpellCorrectionOffer? {
        SpellCorrection.offer(
            prefix: prefix,
            isMisspelled: { [self] word in !isCompleteWord(word) },
            guessesFor: { [self] word in spellGuesses(for: word) }
        )
    }

    private func scheduleAppleSpellCorrection(for snapshot: FocusedFieldSnapshot) {
        guard let candidate = spellCorrectionCandidate(for: snapshot.textBeforeCaret) else {
            return
        }

        debounceTask?.cancel()
        appleSpellTask?.cancel()
        // Drop any in-flight continuation; spelling and completion share the
        // Apple Intelligence gate, and the misspelling is more urgent.
        requestSequence += 1
        let sequence = requestSequence
        let prefix = snapshot.textBeforeCaret
        let element = snapshot.element
        let caret = snapshot.caret
        let word = candidate.word
        let range = candidate.range
        // Hand the model the words *before* the token, not the token itself —
        // so "system admini" steers toward administrator, not a re-read of admini.
        let preceding = SpellCorrection.precedingText(inPrefix: prefix, wordRange: range)

        let pause = Duration.milliseconds(min(tuning.debounceMilliseconds, 400))
        appleSpellTask = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, let self else { return }
            await requestAppleSpellCorrection(
                word: word,
                range: range,
                preceding: preceding,
                prefix: prefix,
                element: element,
                caret: caret,
                sequence: sequence
            )
        }
    }

    private func requestAppleSpellCorrection(
        word: String,
        range: NSRange,
        preceding: String,
        prefix: String,
        element: AXUIElement,
        caret: CaretGeometry?,
        sequence: Int
    ) async {
        DebugLog.log(
            "apple spell request: \(word) preceding=\(preceding.suffix(40).debugDescription)"
        )
        do {
            let replacement = try await AppleIntelligenceEngine.correctSpelling(
                word: word, preceding: preceding
            )
            guard
                sequence == requestSequence,
                !Task.isCancelled,
                lastSnapshotPrefix == prefix,
                activeSuggestion == nil
            else {
                DebugLog.log("apple spell discarded: stale")
                return
            }
            guard
                let offer = SpellCorrection.offer(
                    misspelled: word, range: range, replacement: replacement
                )
            else {
                DebugLog.log("apple spell empty or unchanged")
                // Nothing to fix — fall through to an ordinary continuation.
                guard !completionInFlight else { return }
                if let latestSnapshot, latestSnapshot.textBeforeCaret == prefix {
                    scheduleCompletion(for: latestSnapshot)
                }
                return
            }
            presentCorrection(offer, element: element, caret: caret)
        } catch is CancellationError {
            DebugLog.log("apple spell cancelled", at: .quiet)
        } catch {
            DebugLog.log("apple spell failed: \(error.localizedDescription)", at: .quiet)
            guard
                sequence == requestSequence,
                !Task.isCancelled,
                activeCorrection == nil,
                activeSuggestion == nil,
                !completionInFlight,
                let latestSnapshot
            else { return }
            scheduleCompletion(for: latestSnapshot)
        }
    }

    private func presentCorrection(
        _ offer: SpellCorrectionOffer,
        element: AXUIElement,
        caret: CaretGeometry?
    ) {
        debounceTask?.cancel()
        appleSpellTask?.cancel()
        requestSequence += 1
        activeSuggestion = nil
        activeCorrection = offer
        activeElement = element
        acceptedFromCurrentSuggestion = ""
        activeSuggestionTopLeftY = nil
        showCorrectionOverlay(offer, at: caret)
        updateActivity()
        DebugLog.log(
            "spell correction (\(spellCorrectionEngine.rawValue)): "
                + "\(offer.misspelled) -> \(offer.replacement)"
        )
    }

    private func scheduleCompletion(for snapshot: FocusedFieldSnapshot) {
        let prefix = snapshot.textBeforeCaret
        debounceTask?.cancel()
        appleSpellTask?.cancel()
        guard CompletionSuggestion.shouldTrigger(for: prefix, tuning: tuning) else {
            DebugLog.log("below trigger threshold", at: .verbose)
            updateActivity()
            return
        }

        let element = snapshot.element
        let caret = snapshot.caret
        let pause = Duration.milliseconds(tuning.debounceMilliseconds)
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            completionInFlight = true
            await requestCompletion(prefix: prefix, element: element, caret: caret)
            completionInFlight = false

            // If the writer out-typed or diverged from that answer, start one
            // fresh request from the newest field truth after the usual pause.
            guard
                !Task.isCancelled,
                activeSuggestion == nil,
                activeCorrection == nil,
                let latestSnapshot,
                latestSnapshot.textBeforeCaret != prefix
            else { return }
            scheduleCompletion(for: latestSnapshot)
        }
    }

    private func handleTypedProgress(prefix: String) {
        guard var suggestion = activeSuggestion else { return }

        if prefix.isEmpty || lastSnapshotPrefix == nil {
            dismissSuggestion()
            return
        }

        let previous = (lastSnapshotPrefix ?? "") as NSString
        let current = prefix as NSString
        guard
            current.length >= previous.length,
            current.hasPrefix(previous as String)
        else {
            dismissSuggestion()
            return
        }

        let typed = current.substring(from: previous.length)
        if suggestion.consumeTypedText(typed) {
            activeSuggestion = suggestion
            showOverlay(for: suggestion)
        } else {
            dismissSuggestion()
        }
    }

    private func requestCompletion(
        prefix: String,
        element: AXUIElement,
        caret: CaretGeometry?
    ) async {
        requestSequence += 1
        let sequence = requestSequence

        let context = String(prefix.suffix(2_000))
        let provider = Preferences.provider(from: defaults)
        let ollamaModel = Preferences.ollamaModel(from: defaults)

        var surrounding: String?
        if screenContextEnabled, screenContext.isPermitted {
            surrounding = await ScreenContextProvider.surroundingText()
            DebugLog.log("screen context: \(surrounding?.count ?? 0) chars")
        }
        let memoryDigest = memoryEnabled ? memory.digest() : nil
        let styleProfile = StyleProfileStore.shared.isEmpty ? nil : StyleProfileStore.shared.text

        DebugLog.log("request provider=\(provider.rawValue) contextLen=\(context.count)")
        do {
            let raw = try await generateCompletion(
                provider: provider,
                context: context,
                surrounding: surrounding,
                memory: memoryDigest,
                styleProfile: styleProfile,
                ollamaModel: ollamaModel,
                sequence: sequence,
                prefix: prefix
            )
            guard
                sequence == requestSequence,
                !Task.isCancelled,
                let currentPrefix = lastSnapshotPrefix,
                let typedSinceRequest = Self.typedSuffix(
                    requestPrefix: prefix,
                    currentPrefix: currentPrefix
                )
            else {
                DebugLog.log("response discarded: stale")
                return
            }

            let scope = CompletionSuggestion.scope(
                forContext: context, endsMidWord: endsMidWord(context)
            )
            var suggestion = normalizedSuggestion(raw: raw, context: context, scope: scope)
            DebugLog.log(
                "raw \(raw.debugDescription) tail \(context.suffix(40).debugDescription) "
                    + "scope \(scope) -> \(suggestion.remaining.debugDescription)",
                at: .verbose
            )

            // The on-device model occasionally returns only an echo, which the
            // safety filter correctly removes. One fresh sample is cheaper than
            // making the feature appear broken after a deliberate pause.
            if suggestion.isEmpty, typedSinceRequest.isEmpty {
                DebugLog.log("response filtered empty; retrying once")
                let retry = try await generateCompletion(
                    provider: provider,
                    context: context,
                    surrounding: surrounding,
                    memory: memoryDigest,
                    styleProfile: styleProfile,
                    ollamaModel: ollamaModel,
                    sequence: sequence,
                    prefix: prefix
                )
                suggestion = normalizedSuggestion(raw: retry, context: context, scope: scope)
            }

            if !typedSinceRequest.isEmpty {
                guard suggestion.consumeTypedText(typedSinceRequest) else {
                    DebugLog.log("response discarded: writer diverged")
                    return
                }
            }
            guard !suggestion.isEmpty else {
                DebugLog.log("response empty")
                return
            }
            guard activeCorrection == nil else {
                DebugLog.log("response discarded: spell correction showing")
                return
            }

            DebugLog.log("suggestion: \(suggestion.remaining.count) chars")
            activeSuggestion = suggestion
            activeElement = element
            acceptedFromCurrentSuggestion = ""
            showOverlay(for: suggestion, at: typedSinceRequest.isEmpty ? caret : nil)
            updateActivity()
        } catch {
            // Completion failures stay silent: autocomplete must never interrupt typing.
            DebugLog.log("request failed: \(error.localizedDescription)", at: .quiet)
        }
    }

    private func normalizedSuggestion(
        raw: String,
        context: String,
        scope: CompletionScope
    ) -> CompletionSuggestion {
        var output = raw
        if scope == .word {
            let partial = trailingWord(context)
            output = CompletionSuggestion.wordCompletion(
                forPartial: partial,
                modelSuggestion: raw,
                candidates: spellCompletions(for: partial)
            )
        }
        return CompletionSuggestion(
            rawOutput: output,
            context: context,
            scope: scope,
            tuning: tuning
        )
    }

    // Internal (not private) so tests can drive the real request path with a
    // spy engine installed on RewriteRunner.
    func generateCompletion(
        provider: RewriteProviderChoice,
        context: String,
        surrounding: String?,
        memory: String?,
        styleProfile: String?,
        ollamaModel: String,
        sequence: Int,
        prefix: String
    ) async throws -> String {
        do {
            return try await RewriteRunner.complete(
                provider: provider,
                context: context,
                surrounding: surrounding,
                memory: memory,
                styleProfile: styleProfile,
                directives: directiveChain,
                ollamaModel: ollamaModel
            )
        } catch is CancellationError {
            guard Self.shouldRetryModelCancellation(
                taskIsCancelled: Task.isCancelled,
                sequence: sequence,
                currentSequence: requestSequence,
                prefix: prefix,
                currentPrefix: lastSnapshotPrefix
            ) else {
                throw CancellationError()
            }

            // Foundation Models can cancel an otherwise-current session while
            // the system model is becoming available or another short session
            // is winding down. A single retry recovers that transient case,
            // while the guards above ensure continued typing and focus changes
            // remain immediate cancellations.
            DebugLog.log("model cancelled current completion; retrying once", at: .quiet)
            try await Task.sleep(for: .milliseconds(120))
            guard Self.shouldRetryModelCancellation(
                taskIsCancelled: Task.isCancelled,
                sequence: sequence,
                currentSequence: requestSequence,
                prefix: prefix,
                currentPrefix: lastSnapshotPrefix
            ) else {
                throw CancellationError()
            }

            return try await RewriteRunner.complete(
                provider: provider,
                context: context,
                surrounding: surrounding,
                memory: memory,
                styleProfile: styleProfile,
                directives: directiveChain,
                ollamaModel: ollamaModel
            )
        }
    }

    nonisolated static func shouldRetryModelCancellation(
        taskIsCancelled: Bool,
        sequence: Int,
        currentSequence: Int,
        prefix: String,
        currentPrefix: String?
    ) -> Bool {
        !taskIsCancelled
            && sequence == currentSequence
            && currentPrefix?.hasPrefix(prefix) == true
    }

    nonisolated static func typedSuffix(
        requestPrefix: String,
        currentPrefix: String
    ) -> String? {
        guard currentPrefix.hasPrefix(requestPrefix) else { return nil }
        return String(currentPrefix.dropFirst(requestPrefix.count))
    }

    // A single letter is a genuine, complete English word only as "a" or
    // "I" (either case). The spell checker doesn't reliably flag other lone
    // letters as misspelled (it's answering "is this spelled wrong", not "is
    // this a word"), which made every other one-letter head start ("y"
    // toward "you", "b" toward "be") look like a finished word already.
    nonisolated static func isStandaloneSingleLetterWord(_ letter: Character) -> Bool {
        switch letter {
        case "a", "A", "i", "I": true
        default: false
        }
    }

    // The trailing run of word characters before the caret. Apostrophes count
    // when they sit inside the run — the spell checker judges "don't" as one
    // word, and a scan that stopped at the apostrophe handed it just "t",
    // misreading every contraction as an unfinished word (and the
    // single-letter rule above then offered completions of "t"). Apostrophes
    // at the run's edges are quotation marks, not word characters, so they
    // are trimmed. Covers the typographic apostrophe smart quotes insert.
    nonisolated static func trailingWordFragment(_ prefix: String) -> String {
        var fragment = String(
            prefix.reversed()
                .prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" })
                .reversed()
        )
        while let first = fragment.first, !first.isLetter {
            fragment.removeFirst()
        }
        while let last = fragment.last, !last.isLetter {
            fragment.removeLast()
        }
        return fragment
    }

    private func showOverlay(
        for suggestion: CompletionSuggestion,
        at knownCaret: CaretGeometry? = nil,
        preserveVertical: Bool = false
    ) {
        guard !suggestion.isEmpty else {
            dismissSuggestion()
            return
        }
        guard let element = activeElement else { return }

        let display = boundaryPrefix(
            prefix: lastSnapshotPrefix ?? "", accepted: suggestion.remaining
        ) + suggestion.remaining

        let caret = knownCaret ?? currentCaret(for: element)
        if inlineSuggestions, let caret, ghostEligibility.allows(caret) {
            overlay.show(
                .ghost(
                    text: display,
                    caret: caret,
                    style: .suggestion,
                    fieldFrame: FocusedFieldTracker.frame(of: element)
                ),
                from: .autocomplete
            )
            return
        }

        // The chip sits just below the caret's line, so it covers nothing the
        // writer has already put down — which is what lets it appear anywhere in
        // a line rather than only at the end of one, and what lets it work in
        // apps that cannot report the geometry drawing inline would need.
        let proposedAnchor = caret.map { CGPoint(x: $0.rect.minX, y: $0.rect.maxY + 4) }
            ?? FocusedFieldTracker.fieldEdgeAnchor(for: element)
        guard let proposedAnchor else {
            DebugLog.log("no caret and no usable field frame; suggestion not shown")
            return
        }
        let anchor = CGPoint(
            x: proposedAnchor.x,
            y: Self.stabilizedSuggestionY(
                proposed: proposedAnchor.y,
                previous: activeSuggestionTopLeftY,
                preserveVertical: preserveVertical
            )
        )
        activeSuggestionTopLeftY = anchor.y
        // Detached from the writer's line, a completion has to read as a word.
        // Inline, "documenta" followed by "tion" is obvious; on a chip below the
        // line, a lone "tion" is a puzzle — so the chip shows the whole word and
        // still inserts only the part that is missing.
        overlay.show(
            .suggestion(text: chipText(for: suggestion), anchor: anchor),
            from: .autocomplete
        )
    }

    nonisolated static func stabilizedSuggestionY(
        proposed: CGFloat,
        previous: CGFloat?,
        preserveVertical: Bool
    ) -> CGFloat {
        guard let previous else { return proposed }
        return SuggestionOverlayController.stabilizedPillY(
            proposed: proposed,
            previous: previous,
            preserveVertical: preserveVertical
        )
    }

    private func chipText(for suggestion: CompletionSuggestion) -> String {
        let prefix = lastSnapshotPrefix ?? ""
        let partial = trailingWord(prefix)
        guard !partial.isEmpty, endsMidWord(prefix) else {
            return boundaryPrefix(prefix: prefix, accepted: suggestion.remaining)
                + suggestion.remaining
        }
        return partial + suggestion.remaining
    }

    // Returns " " when the accepted text needs a separating space from the
    // prefix: the prefix ends with a spell-checkable complete word or with
    // sentence punctuation. Mid-word continuations ("execu" → "tion") stay
    // fused on purpose.
    private func boundaryPrefix(prefix: String, accepted: String) -> String {
        guard
            let last = prefix.last,
            let first = accepted.first,
            !last.isWhitespace,
            !first.isWhitespace,
            first.isLetter
        else { return "" }

        if last.isLetter {
            return endsMidWord(prefix) ? "" : " "
        }
        if ".!?…".contains(last) {
            return " "
        }
        return ""
    }

    // Whether the writer is partway through a word. The spell checker is the
    // only thing on hand that can tell "execu" from "digging" — both are just
    // letters up against the caret.
    private func endsMidWord(_ prefix: String) -> Bool {
        guard let last = prefix.last, last.isLetter else { return false }
        let trailing = Self.trailingWordFragment(prefix)
        if let onlyLetter = trailing.first, trailing.count == 1 {
            return !Self.isStandaloneSingleLetterWord(onlyLetter)
        }
        return !isCompleteWord(trailing)
    }

    // The checker's own language, never nil. Automatic detection matches partial
    // English words against other languages — "documenta", "investiga" and
    // "recei" all pass as real words — which made every half-typed word look
    // finished.
    private func isCompleteWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: NSSpellChecker.shared.language(),
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return misspelled.location == NSNotFound
    }

    private func trailingWord(_ prefix: String) -> String {
        Self.trailingWordFragment(prefix)
    }

    private func spellCompletions(for partial: String) -> [String] {
        guard !partial.isEmpty else { return [] }
        return NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: (partial as NSString).length),
            in: partial,
            language: NSSpellChecker.shared.language(),
            inSpellDocumentWithTag: 0
        ) ?? []
    }

    private func spellGuesses(for word: String) -> [String] {
        guard !word.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return NSSpellChecker.shared.guesses(
            forWordRange: range,
            in: word,
            language: NSSpellChecker.shared.language(),
            inSpellDocumentWithTag: 0
        ) ?? []
    }

    private func currentCaret(for element: AXUIElement) -> CaretGeometry? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }
        return FocusedFieldTracker.caretGeometry(for: element, location: selection.location)
    }

    private func showCorrectionOverlay(
        _ offer: SpellCorrectionOffer,
        at knownCaret: CaretGeometry? = nil
    ) {
        guard let element = activeElement else { return }
        let caret = knownCaret ?? currentCaret(for: element)
        let proposedAnchor = caret.map { CGPoint(x: $0.rect.minX, y: $0.rect.maxY + 4) }
            ?? FocusedFieldTracker.fieldEdgeAnchor(for: element)
        guard let proposedAnchor else {
            DebugLog.log("no caret and no usable field frame; correction not shown")
            return
        }
        activeSuggestionTopLeftY = proposedAnchor.y
        overlay.show(
            .suggestion(text: offer.replacement, anchor: proposedAnchor),
            from: .autocomplete
        )
    }

    // Tap order is run order, same contract as the rewrite chain. A change
    // invalidates whatever suggestion is showing — it was built with the old
    // directives.
    func toggleDirective(_ directive: CompletionDirective) {
        if let index = directiveChain.firstIndex(of: directive) {
            directiveChain.remove(at: index)
        } else {
            directiveChain.append(directive)
        }
        Preferences.saveCompletionChain(directiveChain, to: defaults)
        dismissSuggestion()
    }

    func removeDirective(_ directive: CompletionDirective) {
        guard let index = directiveChain.firstIndex(of: directive) else { return }
        directiveChain.remove(at: index)
        Preferences.saveCompletionChain(directiveChain, to: defaults)
        dismissSuggestion()
    }

    /// Swaps a directive with its neighbor so users can reorder without
    /// removing and re-adding. Out-of-range moves are no-ops.
    func moveDirective(_ directive: CompletionDirective, offset: Int) {
        guard let index = directiveChain.firstIndex(of: directive) else { return }
        let target = index + offset
        guard directiveChain.indices.contains(target) else { return }
        directiveChain.swapAt(index, target)
        Preferences.saveCompletionChain(directiveChain, to: defaults)
        dismissSuggestion()
    }

    private func dismissSuggestion() {
        appleSpellTask?.cancel()
        activeSuggestion = nil
        activeCorrection = nil
        activeElement = nil
        activeSuggestionTopLeftY = nil
        overlay.hide(from: .autocomplete)
        updateActivity()
    }

    private func acceptSuggestion(wholeSuggestion: Bool) async {
        if let correction = activeCorrection {
            await acceptCorrection(correction)
            return
        }

        guard
            var suggestion = activeSuggestion,
            let element = activeElement
        else { return }

        let accepted = wholeSuggestion ? suggestion.acceptAll() : suggestion.acceptNextWord()
        guard !accepted.isEmpty else { return }
        let topLeftYBeforeAcceptance = activeSuggestionTopLeftY
        isAcceptingSuggestion = true
        defer { isAcceptingSuggestion = false }

        // FoundationModels strips leading spaces, so word-boundary spacing is
        // computed mechanically: a space is inserted only where the prefix
        // provably ends with a complete word.
        let boundary = boundaryPrefix(prefix: lastSnapshotPrefix ?? "", accepted: accepted)
        guard await AXTextInsertion.insert(boundary + accepted, into: element) else {
            dismissSuggestion()
            return
        }
        acceptedFromCurrentSuggestion += boundary + accepted

        // Chromium fields normalize whitespace on insert; re-sync the baseline
        // to the field's actual text rather than assuming what landed,
        // otherwise the next snapshot mismatches and the suggestion regenerates.
        if let refreshed = FocusedFieldTracker.readPrefix(of: element) {
            lastSnapshotPrefix = refreshed
        } else {
            lastSnapshotPrefix = (lastSnapshotPrefix ?? "") + accepted
        }

        if suggestion.isEmpty {
            let element = activeElement
            if memoryEnabled {
                memory.record(acceptedFromCurrentSuggestion)
                memoryEntryCount = memory.count
            }
            dismissSuggestion()
            if let element {
                scheduleContinuationRequest(element: element)
            }
        } else {
            activeSuggestion = suggestion
            // The accepted word may make Accessibility briefly report a
            // different caret rectangle. Keep the current pill on its line;
            // subsequent ordinary typing can still move it on a real wrap.
            activeSuggestionTopLeftY = topLeftYBeforeAcceptance
            showOverlay(for: suggestion, preserveVertical: true)
        }
    }

    private func acceptCorrection(_ offer: SpellCorrectionOffer) async {
        guard let element = activeElement else { return }
        isAcceptingSuggestion = true
        defer { isAcceptingSuggestion = false }

        let range = CFRange(location: offer.wordLocation, length: offer.wordLength)
        guard await AXTextInsertion.replace(range: range, with: offer.replacement, in: element) else {
            dismissSuggestion()
            return
        }

        if spellMemoryEnabled {
            spellMemory.record(misspelling: offer.misspelled, replacement: offer.replacement)
            spellMemoryEntryCount = spellMemory.count
        }

        if let refreshed = FocusedFieldTracker.readPrefix(of: element) {
            lastSnapshotPrefix = refreshed
        }
        dismissSuggestion()
    }

    // Tabbing through a whole suggestion means the writer wants more; fetch
    // the next continuation without waiting for fresh keystrokes.
    private func scheduleContinuationRequest(element: AXUIElement) {
        guard let prefix = lastSnapshotPrefix,
              CompletionSuggestion.shouldTrigger(for: prefix)
        else { return }

        DebugLog.log("suggestion exhausted; continuing")
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.requestCompletion(prefix: prefix, element: element, caret: nil)
        }
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let coordinator = Unmanaged<AutocompleteCoordinator>
                        .fromOpaque(refcon)
                        .takeUnretainedValue()
                    // Extract Sendable data before hopping to the main actor;
                    // the box carries the non-Sendable CGEvent across.
                    let eventRef = SendableEventRef(event)
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let isShiftPressed = flags.contains(.maskShift)
                    let hasOtherModifiers = !flags.isDisjoint(
                        with: [.maskCommand, .maskControl, .maskAlternate]
                    )
                    let outcome: SendableEventRef? = MainActor.assumeIsolated {
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let tap = coordinator.eventTap {
                                CGEvent.tapEnable(tap: tap, enable: true)
                            }
                            return eventRef
                        }
                        let consumed = coordinator.handleKeyEvent(
                            keyCode: keyCode,
                            isShiftPressed: isShiftPressed,
                            hasOtherModifiers: hasOtherModifiers
                        )
                        return consumed ? nil : eventRef
                    }
                    return outcome?.unmanaged
                },
                userInfo: refcon
            )
        else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    // The event-tap callback runs on the main run loop but is nonisolated, so
    // the non-Sendable CGEvent crosses in an explicitly unchecked box.
    private struct SendableEventRef: @unchecked Sendable {
        let unmanaged: Unmanaged<CGEvent>

        init(_ event: CGEvent) {
            unmanaged = .passUnretained(event)
        }
    }

    private static let tabKeyCode: Int64 = 48
    private static let escapeKeyCode: Int64 = 53

    private var lastTypingRefresh = ContinuousClock.Instant.now

    // Apps that don't emit AX value-changed notifications (most Electron
    // editors) still reach us through key events; use them as a throttled
    // typing signal so suggestions work there too.
    private func noteKeystroke() {
        guard isEnabled else { return }
        let now = ContinuousClock.Instant.now
        guard now - lastTypingRefresh > .milliseconds(250) else { return }
        lastTypingRefresh = now
        tracker.reResolveFocus()
    }

    // Returns true when the key event was consumed and must not reach the app.
    private func handleKeyEvent(
        keyCode: Int64,
        isShiftPressed: Bool,
        hasOtherModifiers: Bool
    ) -> Bool {
        noteKeystroke()

        guard isEnabled, activeSuggestion != nil || activeCorrection != nil else {
            return false
        }

        if keyCode == Self.escapeKeyCode {
            dismissSuggestion()
            return true
        }

        guard keyCode == Self.tabKeyCode else {
            return false
        }

        if isShiftPressed {
            enqueueAccept(wholeSuggestion: true)
        } else if !hasOtherModifiers {
            enqueueAccept(wholeSuggestion: false)
        } else {
            return false
        }
        return true
    }

    // Accepts are serialized: concurrent paste cycles would interleave
    // clipboard writes and garble the inserted text in Chromium fields.
    private var acceptChain: Task<Void, Never>?

    private func enqueueAccept(wholeSuggestion: Bool) {
        let previous = acceptChain
        acceptChain = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await acceptSuggestion(wholeSuggestion: wholeSuggestion)
        }
    }
}
