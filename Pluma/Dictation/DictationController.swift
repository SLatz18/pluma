import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
                if draftReplyEnabled {
                    hotkey.register(draftShortcut, in: .draftReply)
                }
                Task { await prepare() }
            } else {
                hotkey.unregisterHotKey(.dictation)
                hotkey.unregisterHotKey(.draftReply)
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

    @Published private(set) var cleanupChain: [CleanupDirective]

    @Published private(set) var draftShortcut: GlobalShortcut

    @Published var draftReplyEnabled: Bool {
        didSet {
            Preferences.setDraftReplyEnabled(draftReplyEnabled, to: defaults)
            guard draftReplyEnabled != oldValue else { return }
            if draftReplyEnabled && isEnabled {
                hotkey.register(draftShortcut, in: .draftReply)
            } else {
                hotkey.unregisterHotKey(.draftReply)
            }
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
    // there is one Ollama install and one obvious model to talk to. The post
    // keeps RewriteViewModel's copy of the shared preference in step.
    @Published var ollamaModel: String {
        didSet {
            guard ollamaModel != oldValue else { return }
            defaults.set(ollamaModel, forKey: Preferences.ollamaModelKey)
            NotificationCenter.default.post(name: .ollamaModelDidChange, object: self)
        }
    }

    /// Pinned input device UID; empty follows the system default. Capture
    /// resolves this at each session start, so no re-registration is needed.
    @Published private(set) var microphoneUID: String
    @Published private(set) var microphoneName: String

    func setMicrophone(uid: String, name: String) {
        microphoneUID = uid
        microphoneName = uid.isEmpty ? "" : name
        Preferences.setDictationMic(uid: uid, name: name, to: defaults)
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

    // Plain dictation inserts the speaker's words; draft mode treats them as
    // an instruction and inserts a composed reply grounded in the visible
    // conversation. Everything else about the session is identical.
    private enum SessionMode {
        case dictation
        case draftReply
    }

    private var sessionMode: SessionMode = .dictation
    // Captured in parallel with the recording so the thread walk costs no
    // extra wait at release time. The text lives only inside this task.
    private var conversationTask: Task<ConversationContext?, Never>?

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
    private var isFinishing = false
    private var escapeMonitors: [Any] = []
    private var lastHUDAnchor: CGPoint?

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
        cleanupChain = Preferences.cleanupChain(from: defaults)
        draftShortcut = Preferences.draftShortcut(from: defaults)
        draftReplyEnabled = Preferences.draftReplyEnabled(from: defaults)
        cleanupProvider = Preferences.cleanupProvider(from: defaults)
        openAIModel = Preferences.openAICleanupModel(from: defaults)
        ollamaModel = Preferences.ollamaModel(from: defaults)
        microphoneUID = Preferences.dictationMicUID(from: defaults)
        microphoneName = Preferences.dictationMicName(from: defaults)
        isMicPermitted = mic.isGranted

        mic.onChange = { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.isMicPermitted = granted
                self?.updateActivity()
            }
        }

        observeEngine()

        hotkey.onPress = { [weak self] slot in
            guard slot == .dictation || slot == .draftReply else { return }
            Task { @MainActor [weak self] in
                await self?.beginListening(mode: slot == .draftReply ? .draftReply : .dictation)
            }
        }
        hotkey.onRelease = { [weak self] slot in
            guard slot == .dictation || slot == .draftReply else { return }
            Task { @MainActor [weak self] in
                await self?.endListening()
            }
        }

        if isEnabled {
            hotkey.register(shortcut, in: .dictation)
            if draftReplyEnabled {
                hotkey.register(draftShortcut, in: .draftReply)
            }
            Task { await prepare() }
        }
        updateActivity()
        mic.startMonitoring()
        NotificationCenter.default.addObserver(
            forName: .capsShortcutsSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadShortcutsFromPreferences()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .ollamaModelDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard (notification.object as AnyObject?) !== self else { return }
            Task { @MainActor in
                guard let self else { return }
                let stored = Preferences.ollamaModel(from: self.defaults)
                if self.ollamaModel != stored {
                    self.ollamaModel = stored
                }
            }
        }
    }

    private func reloadShortcutsFromPreferences() {
        let updated = Preferences.dictationShortcut(from: defaults)
        let updatedDraft = Preferences.draftShortcut(from: defaults)
        shortcut = updated
        draftShortcut = updatedDraft
        guard isEnabled else { return }
        hotkey.register(updated, in: .dictation)
        if draftReplyEnabled {
            hotkey.register(updatedDraft, in: .draftReply)
        }
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
        if let conflict = Preferences.conflictMessage(
            for: newShortcut, ignoring: .dictation, from: defaults
        ) {
            shortcutConflict = conflict
            return
        }
        shortcutConflict = nil
        shortcut = newShortcut
        Preferences.saveDictationShortcut(newShortcut, to: defaults)
        if isEnabled {
            hotkey.register(newShortcut, in: .dictation)
        }
    }

    func recordDraftShortcut(_ newShortcut: GlobalShortcut) {
        if let conflict = Preferences.conflictMessage(
            for: newShortcut, ignoring: .draftReply, from: defaults
        ) {
            shortcutConflict = conflict
            return
        }
        shortcutConflict = nil
        draftShortcut = newShortcut
        Preferences.saveDraftShortcut(newShortcut, to: defaults)
        if isEnabled && draftReplyEnabled {
            hotkey.register(newShortcut, in: .draftReply)
        }
    }

    func clearShortcutConflict() {
        shortcutConflict = nil
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

    private func beginListening(mode: SessionMode = .dictation) async {
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
        sessionMode = mode
        isSessionActive = true
        isStarting = true
        stopRequested = false
        pressedAt = .now
        savedElement = element

        // Kick off the thread capture while the mic is still warming up, so it
        // is usually finished before the user stops talking. Nothing is stored;
        // the task's value is read once at release and then dropped.
        if mode == .draftReply, Preferences.conversationAwarenessActive(from: defaults) {
            conversationTask = Task.detached(priority: .userInitiated) {
                await ConversationContextProvider.capture()
            }
        } else {
            conversationTask = nil
        }
        savedPrefix = Self.textBeforeCaret(of: element) ?? rememberedPrefix(for: element)
        caret = nil
        caretReadAt = nil
        ghostEligibility = Self.ghostEligibility(of: element)
        liveText = ""
        activity = .listening
        // A new session's first pill anchors at this session's caret, never
        // eased toward a pill left over from the last one. A lingering notice or
        // an autocomplete suggestion can keep the panel visible across a caret
        // move, and without this the "Listening…" pill would spawn on the old
        // line and only jump right when "Transcribing…" replaced it.
        overlay.resetPillAnchorBaseline()
        showHUD()
        installEscapeMonitors()
        // Session boundaries are logged at .quiet on purpose: when a session
        // stalls, the last boundary written names the step that never finished,
        // and that has to be true at every log level.
        DebugLog.log("dictation session started via \(provider.rawValue)", at: .quiet)

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
            let anchor = chipAnchor
            await cancelSession()
            flash(
                systemImage: "exclamationmark.triangle",
                message: error.localizedDescription,
                tone: .failure,
                at: anchor
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
            let anchor = chipAnchor
            await cancelSession()
            flash(systemImage: "mic", message: "Hold to talk", at: anchor)
            return
        }

        // The session stays active until the text lands, so a second press and
        // release inside that window arrives here again. Finishing twice
        // finalizes an analyzer that is already finalizing and inserts the
        // transcript twice.
        guard !isFinishing else { return }
        isFinishing = true

        if let pressedAt {
            DebugLog.log(
                "dictation released after \(ContinuousClock.Instant.now - pressedAt), "
                    + "cleanup \(cleanupEnabled ? "on" : "off")",
                at: .quiet
            )
        }

        activity = .tidying
        // Recording is over the moment the key comes up, but the HUD would
        // keep pulsing until insertion. Switch it to an honest status for the
        // finish/cleanup window — longest when transcription is a network call.
        let isDrafting = sessionMode == .draftReply
        showHUD(
            message: isDrafting ? "Drafting…" : (cleanupEnabled ? "Tidying…" : "Transcribing…"),
            systemImage: isDrafting ? "arrowshape.turn.up.left" : (cleanupEnabled ? "sparkles" : "waveform")
        )
        let finishStarted = ContinuousClock.Instant.now
        let transcript = await engine.finish()
        DebugLog.log(
            "dictation transcribed \(transcript.count) chars in "
                + "\(ContinuousClock.Instant.now - finishStarted)",
            at: .quiet
        )
        // Escape can end the session while transcription or the model is still
        // working. Inserting after that would write text the writer cancelled.
        guard isFinishing else { return }
        guard !transcript.isEmpty else {
            // Cancel first so the notice outlives the session's own hide, but
            // read the anchor before that: this belongs at the caret the writer
            // was dictating into.
            let anchor = chipAnchor
            await cancelSession()
            flash(systemImage: "mic.slash", message: "Nothing was heard", at: anchor)
            return
        }

        if isDrafting, let draft = await draftReply(intent: transcript) {
            guard isFinishing else { return }
            await insert(draft)
            return
        }

        // Draft mode falls through to exactly today's dictation when no
        // conversation was readable or the draft model failed — the user's
        // words are never lost to a feature that could not run.
        let cleanupStarted = ContinuousClock.Instant.now
        let output = await cleanedOutput(for: transcript)
        if cleanupEnabled {
            DebugLog.log(
                "dictation cleanup returned \(output.count) chars in "
                    + "\(ContinuousClock.Instant.now - cleanupStarted) "
                    + "via \(cleanupProvider.rawValue)",
                at: .quiet
            )
        }
        guard isFinishing else { return }

        await insert(DictationTranscript.withoutFragmentPeriod(output))
    }

    // The cleanup half of endListening, factored out so tests can prove the
    // stacked chain reaches the actual request. Falls back to the raw
    // transcript on any failure — losing the user's words is never acceptable.
    func cleanedOutput(for transcript: String) async -> String {
        guard cleanupEnabled else { return transcript }
        return await RewriteRunner.cleanUpDictation(
            provider: cleanupProvider,
            openAIModel: openAIModel,
            ollamaModel: ollamaModel,
            transcript: transcript,
            directives: cleanupChain
        ) ?? transcript
    }

    // Tap order is run order, same contract as the rewrite chain.
    func toggleCleanupDirective(_ directive: CleanupDirective) {
        if let index = cleanupChain.firstIndex(of: directive) {
            cleanupChain.remove(at: index)
        } else {
            cleanupChain.append(directive)
        }
        Preferences.saveCleanupChain(cleanupChain, to: defaults)
    }

    func removeCleanupDirective(_ directive: CleanupDirective) {
        guard let index = cleanupChain.firstIndex(of: directive) else { return }
        cleanupChain.remove(at: index)
        Preferences.saveCleanupChain(cleanupChain, to: defaults)
    }

    /// Swaps a directive with its neighbor so users can reorder without
    /// removing and re-adding. Out-of-range moves are no-ops.
    func moveCleanupDirective(_ directive: CleanupDirective, offset: Int) {
        guard let index = cleanupChain.firstIndex(of: directive) else { return }
        let target = index + offset
        guard cleanupChain.indices.contains(target) else { return }
        cleanupChain.swapAt(index, target)
        Preferences.saveCleanupChain(cleanupChain, to: defaults)
    }

    // The spoken utterance is the *intent*; the visible thread is the ground
    // truth. Both are used for one request and discarded with the session.
    private func draftReply(intent: String) async -> String? {
        let trimmedIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIntent.isEmpty else { return nil }

        guard let conversation = await conversationTask?.value else {
            DebugLog.log("draft mode: no conversation context; inserting plain dictation", at: .quiet)
            return nil
        }

        let memoryDigest = Preferences.memoryEnabled(from: defaults)
            ? MemoryStore.shared.digest() : nil
        let profile = StyleProfileStore.shared.isEmpty ? nil : StyleProfileStore.shared.text

        do {
            let draft = try await RewriteRunner.draftReply(
                provider: cleanupProvider,
                openAIModel: openAIModel,
                ollamaModel: ollamaModel,
                intent: trimmedIntent,
                conversation: conversation.text,
                memory: memoryDigest,
                styleProfile: profile
            )
            DebugLog.log(
                "drafted reply: \(draft.count) chars from \(conversation.source.rawValue) context"
            )
            return draft
        } catch {
            DebugLog.log("draft reply failed: \(error.localizedDescription)", at: .quiet)
            return nil
        }
    }

    private func insert(_ text: String) async {
        defer { resetSession() }

        guard let element = savedElement else { return }
        let insertion = DictationTranscript.insertionText(text, precededBy: savedPrefix)
        guard !insertion.isEmpty else { return }
        DebugLog.log(
            "dictation spacing: prefix \(savedPrefix == nil ? "unknown" : "known"), "
                + "leading space \(insertion.hasPrefix(" ") ? "added" : "omitted")"
        )

        if await AXTextInsertion.insert(insertion, into: element) {
            DebugLog.log("dictation inserted \(insertion.count) chars", at: .quiet)
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
                // Our own synthetic events (the paste that performed this very
                // insertion, Reader's copy) are not user edits — reacting to
                // them wiped the spacing memory moments after it was written.
                if let cgEvent = event.cgEvent, SyntheticEventMarker.isPlumaEvent(cgEvent) {
                    return
                }
                self.forgetRecentInsertion(because: event.type == .keyDown ? "keystroke" : "click")
            }
        }
    }

    private func isDictationChord(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == shortcut.keyCode
            || UInt32(event.keyCode) == draftShortcut.keyCode
    }

    private func forgetRecentInsertion(because reason: String) {
        guard recentInsertion != nil else { return }
        DebugLog.log("dictation spacing memory dropped: \(reason)")
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

    // Every feature that takes over the caret needs one obvious way out, and
    // Escape is the key Reader already answers to. Live only while a session is,
    // so ordinary Escape presses reach the app the writer is typing in.
    private func installEscapeMonitors() {
        guard escapeMonitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor [weak self] in await self?.cancelFromEscape() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            Task { @MainActor [weak self] in await self?.cancelFromEscape() }
            return nil
        }
        escapeMonitors = [global, local].compactMap { $0 }
    }

    private func removeEscapeMonitors() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors = []
    }

    private func cancelFromEscape() async {
        guard isSessionActive else { return }
        // The notice logs itself; a second line for the same instant would
        // clutter the boundary trail this session leaves behind.
        let anchor = chipAnchor
        await cancelSession()
        flash(systemImage: "xmark", message: "Dictation cancelled", at: anchor)
    }

    private func cancelSession() async {
        await engine.cancel()
        resetSession()
        overlay.hide(from: .dictation)
    }

    private func resetSession() {
        removeEscapeMonitors()
        conversationTask?.cancel()
        conversationTask = nil
        sessionMode = .dictation
        isSessionActive = false
        isStarting = false
        stopRequested = false
        isFinishing = false
        pressedAt = nil
        savedElement = nil
        savedPrefix = nil
        caret = nil
        caretReadAt = nil
        lastHUDAnchor = nil
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
    // there. Order is most-precise first: the resolved caret, then a real
    // field's edge, then — for a terminal TUI whose field is a lone cursor cell
    // that answers no caret geometry — that cell. The mouse is the last resort
    // because it is the one anchor with no relationship to where the transcript
    // will land.
    private var chipAnchor: CGPoint {
        if let caret {
            return CGPoint(x: caret.rect.minX, y: caret.rect.maxY + 4)
        }
        if let element = savedElement, let anchor = FocusedFieldTracker.fieldEdgeAnchor(for: element) {
            return anchor
        }
        if let element = savedElement, let anchor = FocusedFieldTracker.caretCellAnchor(for: element) {
            return anchor
        }
        return SuggestionOverlayController.mouseTopLeftPoint()
    }

    // Names the branch chipAnchor took, mirroring its order so the log never
    // claims a source the anchor didn't actually come from.
    private var anchorDerivation: String {
        if let caret {
            return "\(caret.source.rawValue) \(FocusedFieldTracker.describe(caret.rect))"
        }
        if let element = savedElement, let frame = FocusedFieldTracker.frame(of: element) {
            if FocusedFieldTracker.fieldEdgeAnchor(for: element) != nil {
                return "field edge of \(FocusedFieldTracker.describe(frame))"
            }
            if FocusedFieldTracker.caretCellAnchor(for: element) != nil {
                return "caret cell of \(FocusedFieldTracker.describe(frame))"
            }
        }
        return "pointer"
    }

    // The anchor the pill is actually placed at, logged whenever it changes
    // inside a session. A pill that lands wrong is always one of a few things —
    // a probe that answered differently, the field edge standing in, a terminal
    // cursor cell, or nothing at all and the pointer standing in — and they want
    // different fixes. Which one it was should not require guessing, so the label
    // reports the branch chipAnchor actually took rather than merely that a frame
    // existed.
    private func hudAnchor() -> CGPoint {
        let anchor = chipAnchor
        guard lastHUDAnchor != anchor else { return anchor }
        let origin = lastHUDAnchor == nil ? "placed" : "moved"
        DebugLog.log(
            "dictation pill \(origin) at x \(Int(anchor.x)) y \(Int(anchor.y)) via \(anchorDerivation)",
            at: .quiet
        )
        lastHUDAnchor = anchor
        return anchor
    }

    private func showHUD(message: String? = nil, systemImage: String = "mic.fill") {
        // A status message means the key is already up and nothing has been
        // inserted yet, so the caret cannot have moved. Re-reading it here only
        // lets AX geometry jitter shift the pill at the listening→transcribing
        // boundary — the exact seam the writer is watching. Freeze the anchor to
        // the last listening frame instead of refreshing it.
        if message == nil {
            refreshCaret()
        }

        // "Tidying…" and the like are the app talking about itself, not the
        // user's words, so they wear the chip instead of posing as transcript
        // about to be inserted.
        if let message {
            overlay.show(
                .status(
                    systemImage: systemImage,
                    message: message,
                    tone: .accent,
                    anchor: hudAnchor()
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
            overlay.show(.dictation(transcript: liveText, anchor: hudAnchor()), from: .dictation)
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

    // `anchor` is for notices that report on a session already torn down: the
    // teardown drops the caret, so asking for the anchor afterwards yields the
    // pointer. Callers read it first and pass it in. Left nil, a live session
    // still points at its caret, and everything else — permission walls, "Click
    // into a text field first" — has no field to point at and belongs at the
    // pointer by design.
    private func flash(
        systemImage: String,
        message: String,
        tone: OverlayTone = .warning,
        at anchor: CGPoint? = nil
    ) {
        // Every notice the writer sees leaves a line behind. These are the
        // refusals and dead ends — a press that hit a permission wall, an
        // utterance nothing was heard in, a field that rejected the text — and
        // without them the log goes quiet exactly when it is being read.
        DebugLog.log("dictation notice: \(message)", at: .quiet)
        overlay.flash(
            systemImage: systemImage,
            message: message,
            tone: tone,
            atTopLeftPoint: anchor
                ?? (isSessionActive
                    ? chipAnchor : SuggestionOverlayController.mouseTopLeftPoint()),
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
