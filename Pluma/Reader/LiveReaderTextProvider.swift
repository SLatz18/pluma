import ApplicationServices
import Foundation

@MainActor
protocol ReaderTextProviding {
    func currentSource() async -> ReaderTextSource
}

/// Live path: Accessibility selection, then the clipboard. Password fields
/// refuse both.
struct LiveReaderTextProvider: ReaderTextProviding {
    func currentSource() async -> ReaderTextSource {
        var isSecure = false
        var selected: String?
        if AccessibilityPermission.shared.isTrusted, let element = AXFocus.focusedElement() {
            isSecure = AXFocus.isSecureTextField(element)
            selected = AXFocus.selectedText(of: element)
        }
        let clipboard = try? await PasteboardAccess.readString()
        return .resolve(
            isSecureField: isSecure,
            selectedText: selected,
            clipboardText: clipboard
        )
    }
}
