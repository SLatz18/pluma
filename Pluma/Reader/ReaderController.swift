import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation

enum ReaderActivity: Equatable {
    case off
    case idle
    case processing
    case reading
}

@MainActor
final class ReaderController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var activity: ReaderActivity = .off
    @Published private(set) var shortcutConflict: String?
    @Published private(set) var isSpeaking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var voiceEntries: [ReaderVoiceCatalog.Entry] = []
    @Published private(set) var openAIModels: [OpenAITTSCatalogOption] = OpenAITTSCatalog.fallbackModels
    @Published private(set) var openAICatalogStatus: String?
    @Published private(set) var isRefreshingOpenAICatalog = false

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            Preferences.setReaderEnabled(isEnabled, to: defaults)
            if isEnabled {
                hotkey.register(shortcut, in: .readSelection)
                if activity == .off { activity = .idle }
            } else {
                stopSpeaking()
                hotkey.unregisterHotKey(.readSelection)
                activity = .off
            }
        }
    }

    @Published var speechProvider: ReaderSpeechProviderChoice {
        didSet {
            guard speechProvider != oldValue else { return }
            Preferences.setReaderSpeechProvider(speechProvider, to: defaults)
            errorMessage = nil
            if activity == .processing || activity == .reading {
                stopSpeaking()
            }
            rebuildSpeechEngineIfNeeded()
            if speechProvider == .openAI {
                refreshOpenAITTSCatalog()
            }
        }
    }

    @Published var voiceIdentifier: String {
        didSet {
            guard voiceIdentifier != oldValue else { return }
            Preferences.setReaderVoiceIdentifier(voiceIdentifier, to: defaults)
        }
    }

    @Published var openAIVoiceID: String {
        didSet {
            guard openAIVoiceID != oldValue else { return }
            Preferences.setOpenAITTSVoiceID(openAIVoiceID, to: defaults)
            configureOpenAISpeechEngine()
        }
    }

    @Published var openAITTSModelID: String {
        didSet {
            guard openAITTSModelID != oldValue else { return }
            Preferences.setOpenAITTSModelID(openAITTSModelID, to: defaults)
            reconcileOpenAIVoiceForSelectedModel()
            configureOpenAISpeechEngine()
        }
    }

    @Published var rate: Double {
        didSet {
            let clamped = Preferences.clampedReaderRate(rate)
            if clamped != rate {
                rate = clamped
                return
            }
            guard rate != oldValue else { return }
            Preferences.setReaderRate(rate, to: defaults)
        }
    }

    @Published var deliveryMode: ReaderDeliveryMode {
        didSet {
            guard deliveryMode != oldValue else { return }
            Preferences.setReaderDeliveryMode(deliveryMode, to: defaults)
            errorMessage = nil
            if activity == .processing || activity == .reading {
                stopSpeaking()
            }
        }
    }

    var voiceSections: [ReaderVoiceCatalog.Section] {
        ReaderVoiceCatalog.sections(from: voiceEntries)
    }

    var hasPremiumAppleVoices: Bool {
        ReaderVoiceCatalog.hasPremium(in: voiceEntries)
    }

    var openAIVoiceOptions: [OpenAITTSCatalogOption] {
        OpenAITTSCatalog.voices(compatibleWithModel: openAITTSModelID)
    }

    var selectedOpenAIModelDetail: String {
        openAIModels.first(where: { $0.id == openAITTSModelID })?.detail
            ?? OpenAITTSCatalog.detail(forModelID: openAITTSModelID)
    }

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController
    private let injectedSpeech: (any SpeechSpeaking)?
    private var speech: any SpeechSpeaking
    private let textProvider: any ReaderTextProviding
    private let summarizer: any ReaderSummarizing
    private let openAIKeyPresent: () -> Bool
    private var debouncer = HotkeyDebouncer()
    private var pipelineGeneration = 0
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    init(
        defaults: UserDefaults = .standard,
        overlay: SuggestionOverlayController = SuggestionOverlayController(),
        speech: (any SpeechSpeaking)? = nil,
        textProvider: (any ReaderTextProviding)? = nil,
        summarizer: (any ReaderSummarizing)? = nil,
        openAIKeyPresent: @escaping () -> Bool = { OpenAIKey.isPresent }
    ) {
        self.defaults = defaults
        self.overlay = overlay
        self.injectedSpeech = speech
        self.textProvider = textProvider ?? LiveReaderTextProvider()
        self.summarizer = summarizer ?? ConfiguredReaderSummarizer(defaults: defaults)
        self.openAIKeyPresent = openAIKeyPresent

        let enabled = Preferences.readerEnabled(from: defaults)
        let provider = Preferences.readerSpeechProvider(from: defaults)
        let appleVoice = Preferences.readerVoiceIdentifier(from: defaults)
        let cloudVoice = Preferences.openAITTSVoiceID(from: defaults)
        let cloudModel = Preferences.openAITTSModelID(from: defaults)
        let speakingRate = Preferences.readerRate(from: defaults)
        let mode = Preferences.readerDeliveryMode(from: defaults)
        let savedShortcut = Preferences.readerShortcut(from: defaults)

        self.speech = speech ?? Self.makeSpeechEngine(for: provider)
        self.shortcut = savedShortcut
        self.isEnabled = enabled
        self.speechProvider = provider
        self.voiceIdentifier = appleVoice
        self.openAIVoiceID = cloudVoice
        self.openAITTSModelID = cloudModel
        self.rate = speakingRate
        self.deliveryMode = mode
        self.activity = enabled ? .idle : .off

        wireSpeechCallbacks()
        refreshInstalledVoices()
        if provider == .openAI {
            refreshOpenAITTSCatalog()
        }

        hotkey.onPress = { [weak self] slot in
            guard slot == .readSelection else { return }
            Task { @MainActor [weak self] in
                await self?.handlePress()
            }
        }
        if enabled {
            hotkey.register(savedShortcut, in: .readSelection)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func refreshInstalledVoices() {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        voiceEntries = ReaderVoiceCatalog.entries(
            from: AVSpeechSynthesisVoice.speechVoices(),
            languageCode: code
        )
        if voiceIdentifier.isEmpty == false,
           voiceEntries.contains(where: { $0.voice.identifier == voiceIdentifier }) == false {
            voiceIdentifier = ""
        }
    }

    func preferBestInstalledAppleVoiceIfUnset() {
        guard speechProvider == .appleOnDevice, voiceIdentifier.isEmpty else { return }
        let preferred = ReaderVoiceCatalog.preferredIdentifier(in: voiceEntries)
        guard !preferred.isEmpty else { return }
        voiceIdentifier = preferred
    }

    func refreshOpenAITTSCatalog() {
        guard isRefreshingOpenAICatalog == false else { return }
        isRefreshingOpenAICatalog = true
        openAICatalogStatus = openAIKeyPresent()
            ? "Checking model availability with OpenAI…"
            : "Voices come from OpenAI’s documented catalog. Add an API key to check model availability."

        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await OpenAITTSCatalogClient.fetch()
            self.applyOpenAICatalog(snapshot)
            self.isRefreshingOpenAICatalog = false
        }
    }

    private func applyOpenAICatalog(_ snapshot: OpenAITTSCatalogClient.Snapshot) {
        openAIModels = snapshot.models
        openAITTSModelID = OpenAITTSCatalog.resolveModelID(
            preferred: openAITTSModelID,
            available: snapshot.models
        )
        reconcileOpenAIVoiceForSelectedModel()

        if let errorMessage = snapshot.errorMessage, snapshot.modelsFromAPI == false {
            openAICatalogStatus = errorMessage
        } else if snapshot.modelsFromAPI {
            openAICatalogStatus = "Confirmed \(snapshot.models.count) available TTS model\(snapshot.models.count == 1 ? "" : "s") with OpenAI. Voice names use OpenAI’s documented catalog."
        } else {
            openAICatalogStatus = "Showing OpenAI’s documented voice catalog and fallback models."
        }
    }

    private func reconcileOpenAIVoiceForSelectedModel() {
        openAIVoiceID = OpenAITTSCatalog.resolveVoiceID(
            preferred: openAIVoiceID,
            available: openAIVoiceOptions
        )
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        guard let conflict = Self.conflict(for: newShortcut, defaults: defaults) else {
            shortcutConflict = nil
            shortcut = newShortcut
            Preferences.saveReaderShortcut(newShortcut, to: defaults)
            if isEnabled {
                hotkey.register(newShortcut, in: .readSelection)
            }
            return
        }
        shortcutConflict = conflict
    }

    nonisolated static func conflict(
        for shortcut: GlobalShortcut,
        defaults: UserDefaults
    ) -> String? {
        Preferences.conflictMessage(for: shortcut, ignoring: .reader, from: defaults)
    }

    func handleHotkey() {
        Task { await handlePress() }
    }

    func handlePress() async {
        guard isEnabled else { return }
        if activity == .processing || activity == .reading {
            stopSpeaking()
            return
        }
        guard debouncer.shouldFire() else { return }
        await readCurrentSource()
    }

    /// Playground path: speak this text without touching Accessibility or the clipboard.
    func speakPlaygroundText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if activity == .processing || activity == .reading {
            stopSpeaking()
            return
        }
        await prepareAndSpeak(trimmed, readingMessage: "Reading…")
    }

    func stopSpeaking() {
        pipelineGeneration &+= 1
        guard activity == .processing || activity == .reading || speech.isSpeaking else {
            finishReading()
            return
        }
        speech.stop()
        finishReading()
    }

    private func readCurrentSource() async {
        let source = await textProvider.currentSource()
        switch source {
        case .secureField:
            DebugLog.log("reader blocked: secure field", at: .quiet)
            flash(systemImage: "lock.fill", message: "Password fields are never read")
        case .empty:
            DebugLog.log("reader: no selection or clipboard text")
            flash(systemImage: "text.cursor", message: "Select text, or copy it first")
        case .accessibilityDenied:
            DebugLog.log("reader blocked: Accessibility access is required", at: .quiet)
            flash(systemImage: "hand.raised.fill", message: "Grant Accessibility to read selected text")
        case .selection(let text):
            await prepareAndSpeak(text, readingMessage: "Reading…")
        case .clipboard(let text):
            await prepareAndSpeak(text, readingMessage: "Reading clipboard…")
        }
    }

    private func prepareAndSpeak(_ text: String, readingMessage: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil

        if speechProvider == .openAI, openAIKeyPresent() == false {
            flash(systemImage: "key", message: OpenAITranscriptionError.missingKey.localizedDescription)
            return
        }

        guard deliveryMode == .summarizeWhenHelpful else {
            startSpeaking(trimmed, message: readingMessage)
            return
        }

        pipelineGeneration &+= 1
        let generation = pipelineGeneration
        activity = .processing
        overlay.show(
            .status(
                systemImage: "text.alignleft",
                message: "Summarizing for listening…",
                tone: .accent,
                pulses: true,
                anchor: SuggestionOverlayController.mouseTopLeftPoint()
            ),
            from: .reader
        )
        installEscapeMonitors()

        do {
            let summary = try await summarizer.summarize(trimmed)
            guard generation == pipelineGeneration, activity == .processing else { return }
            startSpeaking(summary, message: "Reading summary…")
        } catch {
            guard generation == pipelineGeneration, activity == .processing else { return }
            errorMessage = error.localizedDescription
            DebugLog.log("reader summary failed: \(error.localizedDescription)", at: .quiet)
            finishReading()
            flash(
                systemImage: "exclamationmark.triangle.fill",
                message: "Couldn’t summarize — try again or read verbatim"
            )
        }
    }

    private func startSpeaking(_ text: String, message: String) {
        DebugLog.log("reader start: \(text.count) chars via \(speechProvider.rawValue)")
        activity = .reading
        isSpeaking = true
        let speakingMessage = speechProvider == .openAI ? "Preparing speech…" : message
        let anchor = SuggestionOverlayController.mouseTopLeftPoint()
        overlay.show(
            .status(
                systemImage: "speaker.wave.2.fill",
                message: speakingMessage,
                tone: .accent,
                pulses: true,
                anchor: anchor
            ),
            from: .reader
        )
        installEscapeMonitors()
        configureOpenAISpeechEngine()
        if let openAI = speech as? OpenAISpeechEngine {
            openAI.onPlaybackStarted = { [weak self] in
                self?.overlay.show(
                    .status(
                        systemImage: "speaker.wave.2.fill",
                        message: message,
                        tone: .accent,
                        pulses: true,
                        anchor: SuggestionOverlayController.mouseTopLeftPoint()
                    ),
                    from: .reader
                )
            }
        }
        let voice = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        speech.speak(text, voiceIdentifier: voice, rate: Float(rate))
    }

    private func finishReading() {
        let wasBusy = activity == .processing || activity == .reading
        isSpeaking = false
        if wasBusy {
            overlay.hide(from: .reader)
        }
        activity = isEnabled ? .idle : .off
        removeEscapeMonitors()
    }

    private func flash(systemImage: String, message: String, tone: OverlayTone = .warning) {
        overlay.flashAtMouse(systemImage: systemImage, message: message, tone: tone, from: .reader)
    }

    private func rebuildSpeechEngineIfNeeded() {
        guard injectedSpeech == nil else { return }
        speech.stop()
        speech = Self.makeSpeechEngine(for: speechProvider)
        wireSpeechCallbacks()
    }

    private func wireSpeechCallbacks() {
        speech.onFinish = { [weak self] in
            self?.finishReading()
        }
        if let openAI = speech as? OpenAISpeechEngine {
            openAI.onFailure = { [weak self] message in
                guard let self else { return }
                self.errorMessage = message
                self.flash(
                    systemImage: "exclamationmark.triangle.fill",
                    message: "Couldn’t speak — \(message)"
                )
            }
            configureOpenAISpeechEngine()
        }
    }

    private func configureOpenAISpeechEngine() {
        guard let openAI = speech as? OpenAISpeechEngine else { return }
        openAI.voiceID = openAIVoiceID
        openAI.modelID = openAITTSModelID
    }

    private static func makeSpeechEngine(
        for provider: ReaderSpeechProviderChoice
    ) -> any SpeechSpeaking {
        switch provider {
        case .appleOnDevice: SystemSpeechEngine()
        case .openAI: OpenAISpeechEngine()
        }
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in self?.stopSpeaking() }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            Task { @MainActor in self?.stopSpeaking() }
            return nil
        }
    }

    private func removeEscapeMonitors() {
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}
