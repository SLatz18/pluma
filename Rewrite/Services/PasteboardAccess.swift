import AppKit
import Foundation

/// Privacy-aware helpers for reading and writing the general pasteboard.
/// On macOS 16+, programmatic reads can prompt once under Paste from Other Apps.
enum PasteboardAccess {
    enum ReadError: LocalizedError, Equatable {
        case empty
        case accessDenied
        case noStringContent

        var errorDescription: String? {
            switch self {
            case .empty:
                "Copy some text first, then press the hotkey."
            case .accessDenied:
                "Pasteboard access is denied. Allow Rewrite under Privacy & Security → Paste from Other Apps."
            case .noStringContent:
                "The clipboard does not contain plain text."
            }
        }
    }

    static var accessBehavior: NSPasteboard.AccessBehavior {
        NSPasteboard.general.accessBehavior
    }

    /// Checks for plain-text content without reading it, avoiding a privacy alert.
    static func preflightHasString(on pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.types?.contains(.string) == true {
            return true
        }
        return pasteboard.availableType(from: [.string]) != nil
    }

    static func readString(from pasteboard: NSPasteboard = .general) async throws -> String {
        switch pasteboard.accessBehavior {
        case .alwaysDeny:
            throw ReadError.accessDenied
        case .alwaysAllow, .ask, .default:
            break
        @unknown default:
            break
        }

        guard preflightHasString(on: pasteboard) else {
            throw ReadError.empty
        }

        // The first programmatic read may prompt the user once. That is expected
        // for the hotkey flow and can be managed in System Settings afterward.
        guard let text = pasteboard.string(forType: .string) else {
            throw ReadError.noStringContent
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadError.empty
        }

        return text
    }

    static func writeString(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func openPrivacySettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
