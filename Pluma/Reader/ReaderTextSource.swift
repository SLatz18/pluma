import Foundation

/// Where Reader got the words it is about to speak. Selection wins; clipboard
/// is the fallback only after Accessibility access lets Reader verify the live
/// selection path. Without that access, stale clipboard text must not be read
/// as though it were the user's selection.
/// A focused password field refuses both — the clipboard might be the password
/// the writer just copied to paste.
enum ReaderTextSource: Equatable, Sendable {
    case selection(String)
    case clipboard(String)
    case empty
    case accessibilityDenied
    case secureField

    /// Pure resolution so tests can cover the privacy rules without Accessibility
    /// or a real pasteboard.
    static func resolve(
        isSecureField: Bool,
        selectedText: String?,
        clipboardText: String?
    ) -> ReaderTextSource {
        if isSecureField { return .secureField }
        if let selectedText, selectedText.containsNonWhitespace { return .selection(selectedText) }
        if let clipboardText, clipboardText.containsNonWhitespace { return .clipboard(clipboardText) }
        return .empty
    }

    var spokenText: String? {
        switch self {
        case .selection(let text), .clipboard(let text): text
        case .empty, .accessibilityDenied, .secureField: nil
        }
    }
}

private extension String {
    var containsNonWhitespace: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
