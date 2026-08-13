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

    static func selectedText(of element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &selectedValue
            ) == .success
        else { return nil }
        return selectedValue as? String
    }

    static func isSecureTextField(_ element: AXUIElement) -> Bool {
        var subroleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSubroleAttribute as CFString, &subroleValue
            ) == .success,
            let subrole = subroleValue as? String
        else { return false }
        return subrole == "AXSecureTextField"
    }
}
