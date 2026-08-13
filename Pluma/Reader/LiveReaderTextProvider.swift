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
    func copySelectedText() async -> String? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.accessBehavior != .alwaysDeny else { return nil }
        let previousSnapshot = PasteboardSnapshot(pasteboard)
        let previousChangeCount = pasteboard.changeCount

        guard postCopyShortcut() else { return nil }
        try? await Task.sleep(for: .milliseconds(200))
        guard pasteboard.changeCount != previousChangeCount else { return nil }

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
