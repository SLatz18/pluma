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

    private let defaults: UserDefaults
    private let tracker = FocusedFieldTracker()
    private let overlay = SuggestionOverlayController()
    private let permission = AccessibilityPermission.shared

    private var debounceTask: Task<Void, Never>?
    private var activeSuggestion: CompletionSuggestion?
    private var activeElement: AXUIElement?
    private var lastSnapshotText: String?
    private var requestSequence = 0
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private static let debounceInterval: Duration = .milliseconds(650)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = Preferences.autocompleteEnabled(from: defaults)
        isPermissionGranted = permission.isTrusted

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

    private func startIfPossible() {
        guard permission.isTrusted else {
            updateActivity()
            return
        }
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
            lastSnapshotText = nil
            updateActivity()
            return
        }

        let prefix = snapshot.textBeforeCaret

        if activeSuggestion != nil {
            handleTypedProgress(prefix: prefix)
            lastSnapshotText = snapshot.text
            return
        }

        guard snapshot.text != lastSnapshotText else { return }
        lastSnapshotText = snapshot.text

        debounceTask?.cancel()
        guard CompletionSuggestion.shouldTrigger(for: prefix) else {
            updateActivity()
            return
        }

        let element = snapshot.element
        let caretPoint = snapshot.caretScreenPoint
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.requestCompletion(prefix: prefix, element: element, caretPoint: caretPoint)
        }
    }

    private func handleTypedProgress(prefix: String) {
        guard var suggestion = activeSuggestion else { return }

        if prefix.isEmpty || lastSnapshotText == nil {
            dismissSuggestion()
            return
        }

        let previous = (lastSnapshotText ?? "") as NSString
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
        caretPoint: CGPoint?
    ) async {
        requestSequence += 1
        let sequence = requestSequence

        let context = String(prefix.suffix(2_000))
        let provider = Preferences.provider(from: defaults)
        let ollamaModel = Preferences.ollamaModel(from: defaults)

        do {
            let raw = try await RewriteRunner.complete(
                provider: provider,
                context: context,
                ollamaModel: ollamaModel
            )
            guard
                sequence == requestSequence,
                !Task.isCancelled,
                prefix == lastSnapshotText
            else { return }

            let suggestion = CompletionSuggestion(rawOutput: raw)
            guard !suggestion.isEmpty else { return }

            activeSuggestion = suggestion
            activeElement = element
            showOverlay(for: suggestion, at: caretPoint)
            updateActivity()
        } catch {
            // Completion failures stay silent: autocomplete must never interrupt typing.
        }
    }

    private func showOverlay(for suggestion: CompletionSuggestion, at point: CGPoint? = nil) {
        guard !suggestion.isEmpty else {
            dismissSuggestion()
            return
        }

        if let point {
            overlay.show(text: suggestion.remaining, atTopLeftPoint: point)
        } else if let element = activeElement, let point = currentCaretPoint(for: element) {
            overlay.show(text: suggestion.remaining, atTopLeftPoint: point)
        } else {
            dismissSuggestion()
        }
    }

    private func currentCaretPoint(for element: AXUIElement) -> CGPoint? {
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

        var caretRange = CFRange(location: selection.location, length: 0)
        guard let caretRangeValue = AXValueCreate(.cfRange, &caretRange) else { return nil }

        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                caretRangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return CGPoint(x: rect.maxX + 4, y: rect.minY)
    }

    private func dismissSuggestion() {
        activeSuggestion = nil
        activeElement = nil
        overlay.hide()
        updateActivity()
    }

    private func acceptSuggestion(wholeSuggestion: Bool) {
        guard
            var suggestion = activeSuggestion,
            let element = activeElement
        else { return }

        let accepted = wholeSuggestion ? suggestion.acceptAll() : suggestion.acceptNextWord()
        guard !accepted.isEmpty else { return }

        guard AXTextInsertion.insert(accepted, into: element) else {
            dismissSuggestion()
            return
        }

        lastSnapshotText = (lastSnapshotText ?? "") + accepted

        if suggestion.isEmpty {
            dismissSuggestion()
        } else {
            activeSuggestion = suggestion
            showOverlay(for: suggestion)
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
            acceptSuggestion(wholeSuggestion: true)
        } else if !hasOtherModifiers {
            acceptSuggestion(wholeSuggestion: false)
        } else {
            return false
        }
        return true
    }
}
