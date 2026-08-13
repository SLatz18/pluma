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

    @Published var voiceIdentifier: String {
        didSet {
            guard voiceIdentifier != oldValue else { return }
            Preferences.setReaderVoiceIdentifier(voiceIdentifier, to: defaults)
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

    var voices: [AVSpeechSynthesisVoice] {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matches = all.filter { $0.language.hasPrefix(code) }
        return (matches.isEmpty ? all : matches)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController
    private let speech: any SpeechSpeaking
    private let textProvider: any ReaderTextProviding
    private let summarizer: any ReaderSummarizing
    private var debouncer = HotkeyDebouncer()
    private var pipelineGeneration = 0
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    init(
        defaults: UserDefaults = .standard,
        overlay: SuggestionOverlayController = SuggestionOverlayController(),
        speech: (any SpeechSpeaking)? = nil,
        textProvider: (any ReaderTextProviding)? = nil,
        summarizer: (any ReaderSummarizing)? = nil
    ) {
        self.defaults = defaults
        self.overlay = overlay
        self.speech = speech ?? SystemSpeechEngine()
        self.textProvider = textProvider ?? LiveReaderTextProvider()
        self.summarizer = summarizer ?? ConfiguredReaderSummarizer(defaults: defaults)
        shortcut = Preferences.readerShortcut(from: defaults)
        isEnabled = Preferences.readerEnabled(from: defaults)
        voiceIdentifier = Preferences.readerVoiceIdentifier(from: defaults)
        rate = Preferences.readerRate(from: defaults)
        deliveryMode = Preferences.readerDeliveryMode(from: defaults)
        activity = isEnabled ? .idle : .off

        self.speech.onFinish = { [weak self] in
            self?.finishReading()
        }
        hotkey.onPress = { [weak self] slot in
            guard slot == .readSelection else { return }
            Task { @MainActor [weak self] in
                await self?.handlePress()
            }
        }
        if isEnabled {
            hotkey.register(shortcut, in: .readSelection)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
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
        DebugLog.log("reader start: \(text.count) chars")
        activity = .reading
        isSpeaking = true
        let anchor = SuggestionOverlayController.mouseTopLeftPoint()
        overlay.show(
            .status(
                systemImage: "speaker.wave.2.fill",
                message: message,
                tone: .accent,
                pulses: true,
                anchor: anchor
            ),
            from: .reader
        )
        installEscapeMonitors()
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
