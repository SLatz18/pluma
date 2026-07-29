import ApplicationServices

// The one way to ask "what field is the user typing in right now", shared by
// the selection-rewrite and dictation controllers (previously two identical
// private copies).
enum AXFocus {
    static func focusedElement() -> AXUIElement? {
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
}
