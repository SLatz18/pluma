import AppKit
import ApplicationServices
import SwiftUI

enum DictationActivity: Equatable {
    case off
    case needsPermission
    case preparing
    case idle
    case listening
    case tidying
    case unavailable(String)
}

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var activity: DictationActivity = .off
    @Published private(set) var isMicPermitted: Bool
    @Published private(set) var liveText = ""
    @Published private(set) var shortcutConflict: String?

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Preferences.dictationEnabledKey)
            guard isEnabled != oldValue else { return }
            if isEnabled {
                hotkey.register(shortcut, in: .dictation)
                Task { await prepare() }
            } else {
                hotkey.unregisterHotKey(.dictation)
                Task { await cancelSession() }
            }
            updateActivity()
        }
    }

    @Published var cleanupEnabled: Bool {
        didSet {
            defaults.set(cleanupEnabled, forKey: Preferences.dictationCleanupEnabledKey)
        }
    }

    @Published var provider: DictationProviderChoice {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: Preferences.dictationProviderKey)
            swapEngine()
        }
    }

    @Published var cleanupProvider: CleanupProviderChoice {
        didSet {
            defaults.set(cleanupProvider.rawValue, forKey: Preferences.cleanupProviderKey)
        }
    }

    @Published var openAIModel: OpenAIChatModel {
        didSet {
            defaults.set(openAIModel.rawValue, forKey: Preferences.openAICleanupModelKey)
        }
    }

    // Shared with the rewrite provider's model choice rather than duplicated:
    // there is one Ollama install and one obvious model to talk to.
    @Published var ollamaModel: String {
        didSet {
            defaults.set(ollamaModel, forKey: Preferences.ollamaModelKey)
        }
    }

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController
    private var engine: any DictationTranscribing
    private let mic = MicrophonePermission.shared

    // When a field won't tell us what precedes the caret, the one thing we do
    // know is what we put there ourselves a moment ago.
    private struct RecentInsertion {
        let pid: pid_t
        let lastCharacter: Character
        let at: ContinuousClock.Instant
    }

    private var savedElement: AXUIElement?
    private var savedPrefix: String?
    private var recentInsertion: RecentInsertion?
    private var editMonitor: Any?
    // Re-read as the transcript grows rather than frozen at session start, so
    // the HUD survives the window moving or the field scrolling under it.
    private var caret: CaretGeometry?
    private var caretReadAt: ContinuousClock.Instant?
    private var ghostEligibility = GhostTextEligibility.unknown
    private var pressedAt: ContinuousClock.Instant?
    private var sessionID = 0
    private var isSessionActive = false
    private var isStarting = false
    private var stopRequested = false

    // A tap that never held long enough to say anything is a mis-press, not a
    // zero-length dictation.
    private static let minimumHold: Duration = .milliseconds(300)

    // Long enough to cover pausing to think between two dictated sentences,
    // short enough that returning to an app later isn't treated as continuing.
    private static let insertionRecency: Duration = .seconds(120)

    init(
        defaults: UserDefaults = .standard,
        engine: (any DictationTranscribing)? = nil,
        overlay: SuggestionOverlayController = SuggestionOverlayController()
    ) {
        self.defaults = defaults
        self.overlay = overlay
        let selected = Preferences.dictationProvider(from: defaults)
        self.engine = engine ?? Self.makeEngine(for: selected)
        provider = selected
        shortcut = Preferences.dictationShortcut(from: defaults)
        isEnabled = Preferences.dictationEnabled(from: defaults)
        cleanupEnabled = Preferences.dictationCleanupEnabled(from: defaults)
        cleanupProvider = Preferences.cleanupProvider(from: defaults)
        openAIModel = Preferences.openAICleanupModel(from: defaults)
        ollamaModel = Preferences.ollamaModel(from: defaults)
        isMicPermitted = mic.isGranted

        mic.onChange = { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.isMicPermitted = granted
                self?.updateActivity()
            }
        }

        observeEngine()

        hotkey.onPress = { [weak self] slot in
            guard slot == .dictation else { return }
            Task { @MainActor [weak self] in
                await self?.beginListening()
            }
        }
        hotkey.onRelease = { [weak self] slot in
            guard slot == .dictation else { return }
            Task { @MainActor [weak self] in
                await self?.endListening()
            }
        }

        if isEnabled {
            hotkey.register(shortcut, in: .dictation)
            Task { await prepare() }
        }
        updateActivity()
        mic.startMonitoring()
    }

    private static func makeEngine(
        for provider: DictationProviderChoice
    ) -> any DictationTranscribing {
        switch provider {
        case .appleOnDevice: SpeechTranscriptionEngine()
        case .openAI: OpenAITranscriptionEngine()
        }
    }

    private func observeEngine() {
        engine.onAvailabilityChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateActivity()
            }
        }
        engine.onVolatileText = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.updateLive(text: text)
            }
        }
    }

    private func swapEngine() {
        let outgoing = engine
        Task { await outgoing.cancel() }
        engine = Self.makeEngine(for: provider)
        observeEngine()
        updateActivity()
        if isEnabled {
            Task { await prepare() }
        }
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        guard let conflict = Preferences.conflictMessage(
            for: newShortcut, ignoring: .dictation, from: defaults
        ) else {
            shortcutConflict = nil
            shortcut = newShortcut
            Preferences.saveDictationShortcut(newShortcut, to: defaults)
            if isEnabled {
                hotkey.register(newShortcut, in: .dictation)
            }
            return
        }
        shortcutConflict = conflict
    }

    func requestMicrophonePermission() async {
        await mic.request()
        isMicPermitted = mic.isGranted
        updateActivity()
    }

    func prepare() async {
        await engine.prepare()
        updateActivity()
    }

    private func beginListening() async {
        guard isEnabled, !isSessionActive else { return }

        guard AccessibilityPermission.shared.isTrusted else {
            flash(systemImage: "hand.raised", message: "pluma needs Accessibility access")
            return
        }
        guard mic.isGranted else {
            flash(systemImage: "mic.slash", message: "pluma needs microphone access")
            await requestMicrophonePermission()
            return
        }
        if case .unsupported(let reason) = engine.availability {
            flash(systemImage: "exclamationmark.triangle", message: reason, tone: .failure)
            return
        }
        guard case .ready = engine.availability else {
            flash(systemImage: "arrow.down.circle", message: "Preparing the speech model…")
            await prepare()
            return
        }
        guard let element = AXFocus.focusedElement() else {
            flash(systemImage: "text.cursor", message: "Click into a text field first")
            return
        }

        sessionID += 1
        let session = sessionID
        isSessionActive = true
        isStarting = true
        stopRequested = false
        pressedAt = .now
        savedElement = element
        savedPrefix = Self.textBeforeCaret(of: element) ?? rememberedPrefix(for: element)
        caret = nil
        caretReadAt = nil
        ghostEligibility = Self.ghostEligibility(of: element)
        liveText = ""
        activity = .listening
        showHUD()

        let useScreenContext = Preferences.screenContextEnabled(from: defaults)
        do {
            try await engine.start(contextStrings: {
                guard useScreenContext else { return [] }
                guard let text = await ScreenContextProvider.surroundingText() else { return [] }
                return ScreenContextProvider.contextualStrings(from: text)
            })
        } catch {
            DebugLog.log("dictation start failed: \(error.localizedDescription)", at: .quiet)
            isStarting = false
            await cancelSession()
            flash(
                systemImage: "exclamationmark.triangle",
                message: error.localizedDescription,
                tone: .failure
            )
            return
        }

        guard session == sessionID else { return }
        isStarting = false

        // The key may have been released while the mic and OCR were coming up.
        if stopRequested {
            await endListening()
        }
    }

    private func endListening() async {
        guard isSessionActive else { return }

        // Release can arrive before start() has finished wiring the analyzer;
        // tearing down mid-start would lose the session, so defer instead.
        if isStarting {
            stopRequested = true
            return
        }

        if let pressedAt, ContinuousClock.Instant.now - pressedAt < Self.minimumHold {
            await cancelSession()
            flash(systemImage: "mic", message: "Hold to talk")
            return
        }

        activity = .tidying
        // Recording is over the moment the key comes up, but the HUD would
        // keep pulsing until insertion. Switch it to an honest status for the
        // finish/cleanup window — longest when transcription is a network call.
        showHUD(
            message: cleanupEnabled ? "Tidying…" : "Transcribing…",
            systemImage: cleanupEnabled ? "sparkles" : "waveform"
        )
        let transcript = await engine.finish()
        guard !transcript.isEmpty else {
            await cancelSession()
            flash(systemImage: "mic.slash", message: "Nothing was heard")
            return
        }

        var output = transcript
        if cleanupEnabled, let cleaned = await RewriteRunner.cleanUpDictation(
            provider: cleanupProvider,
            openAIModel: openAIModel,
            ollamaModel: ollamaModel,
            transcript: transcript
        ) {
            output = cleaned
        }

        await insert(DictationTranscript.withoutFragmentPeriod(output))
    }

    private func insert(_ text: String) async {
        defer { resetSession() }

        guard let element = savedElement else { return }
        let insertion = DictationTranscript.insertionText(text, precededBy: savedPrefix)
        guard !insertion.isEmpty else { return }

        if await AXTextInsertion.insert(insertion, into: element) {
            DebugLog.log("dictation inserted \(insertion.count) chars")
            remember(insertion, in: element)
            overlay.hide(from: .dictation)
        } else {
            flash(
                systemImage: "exclamationmark.triangle",
                message: "This field rejected the text",
                tone: .failure
            )
        }
    }

    private func remember(_ insertion: String, in element: AXUIElement) {
        guard let last = insertion.last, let pid = Self.pid(of: element) else { return }
        recentInsertion = RecentInsertion(pid: pid, lastCharacter: last, at: .now)
        startWatchingForEdits()
    }

    // Pressing Return to send a message, or clicking into somewhere else, makes
    // our record of the preceding character worthless — the classic symptom
    // being a leading space dictated into a field the user had just emptied.
    // Only the fact that an event happened matters here, never which key.
    private func startWatchingForEdits() {
        guard editMonitor == nil else { return }
        editMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .keyDown, self.isDictationChord(event) { return }
                self.forgetRecentInsertion()
            }
        }
    }

    private func isDictationChord(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == shortcut.keyCode
    }

    private func forgetRecentInsertion() {
        guard recentInsertion != nil else { return }
        recentInsertion = nil
        if let editMonitor {
            NSEvent.removeMonitor(editMonitor)
            self.editMonitor = nil
        }
    }

    // Matching on the process rather than the element because the fields that
    // need this are the same ones that hand back a fresh, unequal AXUIElement
    // for what is visibly the same text box. Safe only because any keystroke or
    // click since the insertion drops the memory: what makes it trustworthy is
    // that nothing has happened to the text since we wrote it.
    private func rememberedPrefix(for element: AXUIElement) -> String? {
        guard
            let recent = recentInsertion,
            Self.pid(of: element) == recent.pid,
            ContinuousClock.Instant.now - recent.at < Self.insertionRecency
        else { return nil }
        DebugLog.log("caret text unavailable; spacing from our last insertion")
        return String(recent.lastCharacter)
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func cancelSession() async {
        await engine.cancel()
        resetSession()
        overlay.hide(from: .dictation)
    }

    private func resetSession() {
        isSessionActive = false
        isStarting = false
        stopRequested = false
        pressedAt = nil
        savedElement = nil
        savedPrefix = nil
        caret = nil
        caretReadAt = nil
        ghostEligibility = .unknown
        liveText = ""
        updateActivity()
    }

    private func updateLive(text: String) {
        guard isSessionActive, activity == .listening else { return }
        liveText = text
        showHUD()
    }

    private func updateActivity() {
        if isSessionActive { return }
        if !isEnabled {
            activity = .off
            return
        }
        switch engine.availability {
        case .unsupported(let reason):
            activity = .unavailable(reason)
        case .checking, .preparing:
            activity = .preparing
        case .ready:
            // Read the published snapshot, not the singleton, so the status
            // row and the permission notice can never disagree.
            activity = isMicPermitted ? .idle : .needsPermission
        }
    }

    // Volatile transcripts arrive several times a second. Re-reading the caret
    // on every one would be a burst of AX round trips for a cursor that has not
    // moved, so cache it briefly — and when a read fails, keep the last known
    // geometry rather than letting the HUD teleport mid-sentence.
    private static let caretRefreshInterval: Duration = .milliseconds(80)

    private func refreshCaret() {
        guard let element = savedElement else { return }
        let now = ContinuousClock.Instant.now
        if let caretReadAt, now - caretReadAt < Self.caretRefreshInterval { return }
        caretReadAt = now

        guard let range = Self.caretRange(of: element) else { return }
        if let fresh = FocusedFieldTracker.caretGeometry(for: element, location: range.location) {
            caret = fresh
        }
    }

    // Just below the caret's line, so a chip never covers the words already
    // there. The mouse is the last resort because it is the one anchor with no
    // relationship to where the transcript will land.
    private var chipAnchor: CGPoint {
        if let caret {
            return CGPoint(x: caret.rect.minX, y: caret.rect.maxY + 4)
        }
        if let element = savedElement, let anchor = FocusedFieldTracker.fieldEdgeAnchor(for: element) {
            return anchor
        }
        return SuggestionOverlayController.mouseTopLeftPoint()
    }

    private func showHUD(message: String? = nil, systemImage: String = "mic.fill") {
        refreshCaret()

        // "Tidying…" and the like are the app talking about itself, not the
        // user's words, so they wear the chip instead of posing as transcript
        // about to be inserted.
        if let message {
            overlay.show(
                .status(
                    systemImage: systemImage,
                    message: message,
                    tone: .accent,
                    anchor: chipAnchor
                ),
                from: .dictation
            )
            return
        }

        // Follows the same setting suggestions do. Dictation and autocomplete
        // speak from the same pill in the same place, so one of them drawing
        // into the line while the other sat below it would read as two features
        // that had never met.
        guard
            Preferences.inlineSuggestions(from: defaults),
            let caret, ghostEligibility.allows(caret)
        else {
            overlay.show(.dictation(transcript: liveText, anchor: chipAnchor), from: .dictation)
            return
        }
        overlay.show(
            .ghost(
                text: liveText.isEmpty ? "Listening…" : liveText,
                caret: caret,
                style: .dictation,
                fieldFrame: savedElement.flatMap { FocusedFieldTracker.frame(of: $0) }
            ),
            from: .dictation
        )
    }

    private func flash(
        systemImage: String,
        message: String,
        tone: OverlayTone = .warning
    ) {
        overlay.flash(
            systemImage: systemImage,
            message: message,
            tone: tone,
            atTopLeftPoint: isSessionActive
                ? chipAnchor : SuggestionOverlayController.mouseTopLeftPoint(),
            from: .dictation
        )
    }

    private static func caretRange(of element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    // Only the character immediately before the caret matters, but AX gives us
    // the whole value, so trim to keep nothing large in memory.
    private static func textBeforeCaret(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
            let value = valueRef as? String,
            let range = caretRange(of: element)
        else { return nil }

        let nsValue = value as NSString
        guard range.location >= 0, range.location <= nsValue.length else { return nil }
        let prefix = String(nsValue.substring(to: range.location).suffix(8))
        // An empty prefix means either a genuinely empty field or a Chromium
        // field reporting the caret as 0 regardless of its contents. Those need
        // opposite spacing, so report unknown and let the caller decide.
        return prefix.isEmpty ? nil : prefix
    }

    // Read once at the start of a session: nothing is inserted until the key
    // comes up, so the caret does not move while it is held.
    private static func ghostEligibility(of element: AXUIElement) -> GhostTextEligibility {
        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
            let value = valueRef as? String,
            let range = caretRange(of: element)
        else { return .unknown }

        return .of(text: value, caretLocation: range.location)
    }
}
