import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
protocol ReaderTextProviding {
    func currentSource() async -> ReaderTextSource
}

struct ReaderFocusSnapshot: Equatable, Sendable {
    let isAccessibilityTrusted: Bool
    let isSecureField: Bool
    let selectedText: String?
}

@MainActor
protocol ReaderFocusReading {
    func currentSnapshot() -> ReaderFocusSnapshot
}

@MainActor
protocol ReaderSelectionCopying {
    func copySelectedText() async -> String?
}

struct SystemReaderFocusReader: ReaderFocusReading {
    func currentSnapshot() -> ReaderFocusSnapshot {
        guard AccessibilityPermission.shared.isTrusted else {
            return ReaderFocusSnapshot(
                isAccessibilityTrusted: false,
                isSecureField: false,
                selectedText: nil
            )
        }
        guard let element = AXFocus.focusedElement() else {
            return ReaderFocusSnapshot(
                isAccessibilityTrusted: true,
                isSecureField: false,
                selectedText: nil
            )
        }
        return ReaderFocusSnapshot(
            isAccessibilityTrusted: true,
            isSecureField: AXFocus.isSecureTextField(element),
            selectedText: AXFocus.selectedText(of: element)
        )
    }
}

/// Chromium editors such as Google Docs do not expose selected text through
/// Accessibility. Copy the live selection, read it, then restore the user's
/// previous clipboard so Reader behaves like the native-app path.
struct SystemReaderSelectionCopier: ReaderSelectionCopying {
    private static let shortcutModifierMask: CGEventFlags = [
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskShift
    ]
    private static let modifierReleaseTimeout: Duration = .seconds(2)
    private static let modifierPollInterval: Duration = .milliseconds(10)

    func copySelectedText() async -> String? {
        // Reader is normally launched with Caps-L, which expands to the Hyper
        // modifiers. Posting Command-C before that chord is released can turn
        // the synthetic copy into another app's Hyper-C global shortcut. Wait
        // for the initiating chord to clear so the event remains Command-C.
        // With the in-app Caps expander no real modifier flags are ever set,
        // so the wait must also ask the expander whether Caps is still held.
        guard await waitForShortcutModifiersToRelease() else {
            DebugLog.log("reader copy: chord still held after timeout; giving up", at: .quiet)
            return nil
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.accessBehavior != .alwaysDeny else { return nil }
        let previousSnapshot = PasteboardSnapshot(pasteboard)
        let previousChangeCount = pasteboard.changeCount

        guard postCopyShortcut() else { return nil }
        try? await Task.sleep(for: .milliseconds(200))
        guard pasteboard.changeCount != previousChangeCount else {
            DebugLog.log("reader copy: ⌘C produced no pasteboard change", at: .quiet)
            return nil
        }

        let copiedChangeCount = pasteboard.changeCount
        let copiedText = pasteboard.accessBehavior == .alwaysDeny
            ? nil
            : pasteboard.string(forType: .string)

        // Do not clobber a newer copy the user made while Reader was capturing.
        if pasteboard.changeCount == copiedChangeCount {
            previousSnapshot.restore(to: pasteboard)
        }
        return copiedText
    }

    static func hasHeldShortcutModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(shortcutModifierMask).isEmpty
    }

    @MainActor
    private func waitForShortcutModifiersToRelease() async -> Bool {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: Self.modifierReleaseTimeout)

        while Self.hasHeldShortcutModifiers(CGEventSource.flagsState(.hidSystemState))
            || CapsLockExpander.shared.isCapsChordHeld {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: Self.modifierPollInterval)
        }
        let waited = started.duration(to: clock.now)
        if waited > .milliseconds(20) {
            DebugLog.log("reader copy: waited \(waited) for chord release")
        }
        return true
    }

    private func postCopyShortcut() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
            )
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // Marked so our own Caps tap and edit monitors leave these alone.
        SyntheticEventMarker.mark(keyDown)
        SyntheticEventMarker.mark(keyUp)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

/// Live path: Accessibility selection, copied live selection, then the
/// clipboard. Password fields refuse every source. When Accessibility is not
/// trusted, stop instead of presenting unrelated clipboard text as a selection.
struct LiveReaderTextProvider: ReaderTextProviding {
    private let focusReader: any ReaderFocusReading
    private let selectionCopier: any ReaderSelectionCopying

    init(
        focusReader: any ReaderFocusReading = SystemReaderFocusReader(),
        selectionCopier: any ReaderSelectionCopying = SystemReaderSelectionCopier()
    ) {
        self.focusReader = focusReader
        self.selectionCopier = selectionCopier
    }

    func currentSource() async -> ReaderTextSource {
        let focus = focusReader.currentSnapshot()
        if focus.isSecureField { return .secureField }
        if let selected = focus.selectedText, selected.containsNonWhitespace {
            return .selection(selected)
        }

        guard focus.isAccessibilityTrusted else {
            return .accessibilityDenied
        }

        if
            let copiedSelection = await selectionCopier.copySelectedText(),
            copiedSelection.containsNonWhitespace
        {
            return .selection(copiedSelection)
        }

        let clipboard = try? await PasteboardAccess.readString()
        return .resolve(
            isSecureField: false,
            selectedText: nil,
            clipboardText: clipboard
        )
    }
}

private extension String {
    var containsNonWhitespace: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
