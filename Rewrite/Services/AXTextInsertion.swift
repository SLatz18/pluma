import AppKit
import ApplicationServices

@MainActor
enum AXTextInsertion {
    static func insert(_ text: String, into element: AXUIElement) -> Bool {
        let direct = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        ) == .success
        if direct { return true }

        // Chromium/Electron fields often refuse the AX write but accept paste.
        return paste(text)
    }

    private static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if let previous {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(previous, forType: .string)
            }
        }
        return true
    }
}
