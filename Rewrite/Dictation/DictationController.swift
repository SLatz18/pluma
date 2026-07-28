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

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay = SuggestionOverlayController()
    private let engine: SpeechTranscriptionEngine
    private let mic = MicrophonePermission.shared

    private var savedElement: AXUIElement?
    private var savedPrefix: String?
    private var anchor: CGPoint = .zero
    private var pressedAt: ContinuousClock.Instant?
    private var sessionID = 0
    private var isSessionActive = false
    private var isStarting = false
    private var stopRequested = false

    // A tap that never held long enough to say anything is a mis-press, not a
    // zero-length dictation.
    private static let minimumHold: Duration = .milliseconds(300)

    init(defaults: UserDefaults = .standard, engine: SpeechTranscriptionEngine? = nil) {
        self.defaults = defaults
        self.engine = engine ?? SpeechTranscriptionEngine()
        shortcut = Preferences.dictationShortcut(from: defaults)
        isEnabled = Preferences.dictationEnabled(from: defaults)
        cleanupEnabled = Preferences.dictationCleanupEnabled(from: defaults)
        isMicPermitted = mic.isGranted

        mic.onChange = { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.isMicPermitted = granted
                self?.updateActivity()
            }
        }

        self.engine.onAvailabilityChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateActivity()
            }
        }
        self.engine.onVolatileText = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.updateLive(text: text)
            }
        }

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

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        shortcut = newShortcut
        Preferences.saveDictationShortcut(newShortcut, to: defaults)
        if isEnabled {
            hotkey.register(newShortcut, in: .dictation)
        }
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
            flash(systemImage: "hand.raised", message: "Rewrite needs Accessibility access")
            return
        }
        guard mic.isGranted else {
            flash(systemImage: "mic.slash", message: "Rewrite needs microphone access")
            await requestMicrophonePermission()
            return
        }
        if case .unsupported(let reason) = engine.availability {
            flash(systemImage: "exclamationmark.triangle", message: reason)
            return
        }
        guard case .ready = engine.availability else {
            flash(systemImage: "arrow.down.circle", message: "Preparing the speech model…")
            await prepare()
            return
        }
        guard let element = Self.focusedElement() else {
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
        savedPrefix = Self.textBeforeCaret(of: element)
        anchor = Self.caretAnchor(of: element) ?? SuggestionOverlayController.mouseTopLeftPoint()
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
            DebugLog.log("dictation start failed: \(error.localizedDescription)")
            isStarting = false
            await cancelSession()
            flash(systemImage: "exclamationmark.triangle", message: error.localizedDescription)
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
        let transcript = await engine.finish()
        guard !transcript.isEmpty else {
            await cancelSession()
            flash(systemImage: "mic.slash", message: "Nothing was heard")
            return
        }

        var output = transcript
        if cleanupEnabled {
            showHUD(message: "Tidying…", systemImage: "sparkles")
            if let cleaned = await RewriteRunner.cleanUpDictation(
                provider: Preferences.provider(from: defaults),
                transcript: transcript,
                ollamaModel: Preferences.ollamaModel(from: defaults)
            ) {
                output = cleaned
            }
        }

        await insert(output)
    }

    private func insert(_ text: String) async {
        defer { resetSession() }

        guard let element = savedElement else { return }
        let insertion = DictationTranscript.insertionText(text, precededBy: savedPrefix)
        guard !insertion.isEmpty else { return }

        if await AXTextInsertion.insert(insertion, into: element) {
            DebugLog.log("dictation inserted \(insertion.count) chars")
            overlay.hide()
        } else {
            flash(systemImage: "exclamationmark.triangle", message: "This field rejected the text")
        }
    }

    private func cancelSession() async {
        await engine.cancel()
        resetSession()
        overlay.hide()
    }

    private func resetSession() {
        isSessionActive = false
        isStarting = false
        stopRequested = false
        pressedAt = nil
        savedElement = nil
        savedPrefix = nil
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
            activity = mic.isGranted ? .idle : .needsPermission
        }
    }

    private func showHUD(message: String? = nil, systemImage: String = "mic.fill") {
        if let message {
            overlay.show(
                content: StatusOverlayView(systemImage: systemImage, message: message),
                atTopLeftPoint: anchor
            )
        } else {
            overlay.show(
                content: DictationHUDView(text: liveText),
                atTopLeftPoint: anchor
            )
        }
    }

    private func flash(systemImage: String, message: String) {
        overlay.show(
            content: StatusOverlayView(systemImage: systemImage, message: message),
            atTopLeftPoint: isSessionActive
                ? anchor : SuggestionOverlayController.mouseTopLeftPoint()
        )
        Task { [overlay] in
            try? await Task.sleep(for: .seconds(2.5))
            overlay.hide()
        }
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue
            ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        return (focusedValue as! AXUIElement)
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
        return String(nsValue.substring(to: range.location).suffix(8))
    }

    private static func caretAnchor(of element: AXUIElement) -> CGPoint? {
        guard let range = caretRange(of: element) else { return nil }
        return FocusedFieldTracker.caretPoint(for: element, location: range.location)
    }
}
