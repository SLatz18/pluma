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

    @Published private(set) var isScreenContextPermitted: Bool
    @Published private(set) var memoryEntryCount: Int

    private let defaults: UserDefaults
    private let tracker = FocusedFieldTracker()
    private let overlay: SuggestionOverlayController
    private let permission = AccessibilityPermission.shared
    private let screenContext = ScreenContextProvider.shared
    private let memory = MemoryStore.shared

    private var debounceTask: Task<Void, Never>?
    private var activeSuggestion: CompletionSuggestion?
    private var activeElement: AXUIElement?
    private var lastSnapshotPrefix: String?
    private var ghostEligibility = GhostTextEligibility.unknown
    private var acceptedFromCurrentSuggestion = ""
    private var requestSequence = 0
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private static let debounceInterval: Duration = .milliseconds(650)

    init(defaults: UserDefaults = .standard, overlay: SuggestionOverlayController = SuggestionOverlayController()) {
        self.defaults = defaults
        self.overlay = overlay
        isEnabled = Preferences.autocompleteEnabled(from: defaults)
        screenContextEnabled = Preferences.screenContextEnabled(from: defaults)
        memoryEnabled = Preferences.memoryEnabled(from: defaults)
        isPermissionGranted = permission.isTrusted
        isScreenContextPermitted = screenContext.isPermitted
        memoryEntryCount = memory.count
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
        } else if activeSuggestion != nil {
            activity = .suggesting
        } else {
            activity = .watching
        }
    }

    private func handleSnapshot(_ snapshot: FocusedFieldSnapshot?) {
        guard let snapshot else {
            debounceTask?.cancel()
            dismissSuggestion()
            lastSnapshotPrefix = nil
            updateActivity()
            return
        }

        let prefix = snapshot.textBeforeCaret
        // Decided here rather than at draw time: the field's whole text is in
        // hand now, and re-reading it on every repaint would cost an AX round
        // trip per keystroke.
        ghostEligibility = snapshot.ghostEligibility

        if activeSuggestion != nil {
            handleTypedProgress(prefix: prefix)
            lastSnapshotPrefix = prefix
            return
        }

        guard prefix != lastSnapshotPrefix else { return }
        lastSnapshotPrefix = prefix
        DebugLog.log("snapshot len=\(prefix.count) caret=\(snapshot.caretLocation)", at: .verbose)

        debounceTask?.cancel()
        guard CompletionSuggestion.shouldTrigger(for: prefix) else {
            DebugLog.log("below trigger threshold", at: .verbose)
            updateActivity()
            return
        }

        let element = snapshot.element
        let caret = snapshot.caret
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.requestCompletion(prefix: prefix, element: element, caret: caret)
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
            let raw = try await RewriteRunner.complete(
                provider: provider,
                context: context,
                surrounding: surrounding,
                memory: memoryDigest,
                styleProfile: styleProfile,
                ollamaModel: ollamaModel
            )
            guard
                sequence == requestSequence,
                !Task.isCancelled,
                prefix == lastSnapshotPrefix
            else {
                DebugLog.log("response discarded: stale")
                return
            }

            let scope = CompletionSuggestion.scope(
                forContext: context, endsMidWord: endsMidWord(context)
            )
            var output = raw
            if scope == .word {
                let partial = trailingWord(context)
                output = CompletionSuggestion.wordCompletion(
                    forPartial: partial,
                    modelSuggestion: raw,
                    candidates: spellCompletions(for: partial)
                )
            }
            let suggestion = CompletionSuggestion(rawOutput: output, context: context, scope: scope)
            DebugLog.log(
                "raw \(raw.debugDescription) tail \(context.suffix(40).debugDescription) "
                    + "scope \(scope) -> \(suggestion.remaining.debugDescription)",
                at: .verbose
            )
            guard !suggestion.isEmpty else {
                DebugLog.log("response empty")
                return
            }

            DebugLog.log("suggestion: \(suggestion.remaining.count) chars")
            activeSuggestion = suggestion
            activeElement = element
            acceptedFromCurrentSuggestion = ""
            showOverlay(for: suggestion, at: caret)
            updateActivity()
        } catch {
            // Completion failures stay silent: autocomplete must never interrupt typing.
            DebugLog.log("request failed: \(error.localizedDescription)", at: .quiet)
        }
    }

    private func showOverlay(for suggestion: CompletionSuggestion, at knownCaret: CaretGeometry? = nil) {
        guard !suggestion.isEmpty else {
            dismissSuggestion()
            return
        }
        guard let element = activeElement else { return }

        let display = boundaryPrefix(
            prefix: lastSnapshotPrefix ?? "", accepted: suggestion.remaining
        ) + suggestion.remaining

        let caret = knownCaret ?? currentCaret(for: element)
        if let caret, ghostEligibility.allows(caret) {
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

        // Mid-line and right-to-left carets fall back to the chip, sitting just
        // below the line so it never covers what the user already wrote.
        let anchor = caret.map { CGPoint(x: $0.rect.minX, y: $0.rect.maxY + 4) }
            ?? FocusedFieldTracker.fieldEdgeAnchor(for: element)
        guard let anchor else {
            DebugLog.log("no caret and no usable field frame; suggestion not shown")
            return
        }
        overlay.show(.suggestionChip(text: display, anchor: anchor), from: .autocomplete)
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
        let trailing = String(prefix.reversed().prefix(while: \.isLetter).reversed())
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
        String(prefix.reversed().prefix(while: \.isLetter).reversed())
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

    private func dismissSuggestion() {
        activeSuggestion = nil
        activeElement = nil
        overlay.hide(from: .autocomplete)
        updateActivity()
    }

    private func acceptSuggestion(wholeSuggestion: Bool) async {
        guard
            var suggestion = activeSuggestion,
            let element = activeElement
        else { return }

        let accepted = wholeSuggestion ? suggestion.acceptAll() : suggestion.acceptNextWord()
        guard !accepted.isEmpty else { return }

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
            showOverlay(for: suggestion)
        }
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

        guard isEnabled, activeSuggestion != nil else {
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
