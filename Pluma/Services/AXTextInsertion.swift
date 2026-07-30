import AppKit
import ApplicationServices

@MainActor
enum AXTextInsertion {
    static func insert(_ text: String, into element: AXUIElement) async -> Bool {
        let wrote = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        ) == .success

        // Chromium web fields report success on AX writes they silently
        // ignore, so a "successful" write still needs verification.
        if wrote, await confirmInsertion(of: text, into: element) {
            return true
        }
        if wrote {
            DebugLog.log("direct AX write had no effect; falling back to paste")
        }
        return paste(text)
    }

    // Selects an absolute UTF-16 range, then writes through the same path as a
    // caret insert — selected text is replaced rather than appended.
    static func replace(
        range: CFRange,
        with text: String,
        in element: AXUIElement
    ) async -> Bool {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else { return false }
        guard
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, axRange
            ) == .success
        else {
            DebugLog.log("failed to select range for replace", at: .quiet)
            return false
        }
        return await insert(text, into: element)
    }

    private static func confirmInsertion(of text: String, into element: AXUIElement) async -> Bool {
        for attempt in 0...1 {
            if checkInsertion(of: text, into: element) { return true }
            if attempt == 0 {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return false
    }

    // Verifies the text immediately before the caret now matches what was
    // inserted. Unreadable fields are trusted rather than double-inserted.
    private static func checkInsertion(of text: String, into element: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
            let value = valueRef as? String,
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
            ) == .success,
            let rangeRef,
            CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return true }

        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return true }

        let nsValue = value as NSString
        let insertedLength = (text as NSString).length
        let start = selection.location - insertedLength
        guard start >= 0, selection.location <= nsValue.length else { return false }

        let slice = nsValue.substring(with: NSRange(location: start, length: insertedLength))
        return slice.compare(text, options: .caseInsensitive) == .orderedSame
    }

    // Paste cycles are burst-aware: rapid sequential accepts must not let one
    // cycle's delayed clipboard restore clobber the next cycle's paste.
    private static var savedClipboard: String??
    private static var restoreTask: Task<Void, Never>?

    private static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        if savedClipboard == nil {
            savedClipboard = pasteboard.string(forType: .string)
        }
        restoreTask?.cancel()
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

        restoreTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            if let saved = savedClipboard, let value = saved {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            savedClipboard = nil
        }
        return true
    }
}
