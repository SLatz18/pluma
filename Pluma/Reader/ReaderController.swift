import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation

enum ReaderActivity: Equatable {
    case off
    case idle
    case reading
}

@MainActor
final class ReaderController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var activity: ReaderActivity = .off
    @Published private(set) var shortcutConflict: String?
    @Published private(set) var isSpeaking = false

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
    private var debouncer = HotkeyDebouncer()
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    init(
        defaults: UserDefaults = .standard,
        overlay: SuggestionOverlayController = SuggestionOverlayController(),
        speech: (any SpeechSpeaking)? = nil,
        textProvider: (any ReaderTextProviding)? = nil
    ) {
        self.defaults = defaults
        self.overlay = overlay
        self.speech = speech ?? SystemSpeechEngine()
        self.textProvider = textProvider ?? LiveReaderTextProvider()
        shortcut = Preferences.readerShortcut(from: defaults)
        isEnabled = Preferences.readerEnabled(from: defaults)
        voiceIdentifier = Preferences.readerVoiceIdentifier(from: defaults)
        rate = Preferences.readerRate(from: defaults)
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
        if activity == .reading {
            stopSpeaking()
            return
        }
        guard debouncer.shouldFire() else { return }
        await readCurrentSource()
    }

    /// Playground path: speak this text without touching Accessibility or the clipboard.
    func speakPlaygroundText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if activity == .reading {
            stopSpeaking()
            return
        }
        startSpeaking(text, message: "Reading…")
    }

    func stopSpeaking() {
        guard activity == .reading || speech.isSpeaking else {
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
            flash(systemImage: "text.cursor", message: "Select some text first")
        case .selection(let text):
            startSpeaking(text, message: "Reading…")
        case .clipboard(let text):
            startSpeaking(text, message: "Reading clipboard…")
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
        isSpeaking = false
        if activity == .reading {
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
