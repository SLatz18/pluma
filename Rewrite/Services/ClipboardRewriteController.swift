import AppKit
import Foundation

/// Implements the sandbox-legal universal flow (issue #12):
/// user copies text (Cmd+C), presses the global hotkey, the clipboard's
/// text is rewritten in place, and the user pastes (Cmd+V).
/// Works in apps where Services pasteback is unavailable (e.g. Google Docs).
@MainActor
final class ClipboardRewriteController {
    static let shared = ClipboardRewriteController()

    private var isRewriting = false
    private var lastOriginal: String?
    private var lastResult: String?

    private init() {}

    func handleHotkey() {
        guard !isRewriting else { return }
        isRewriting = true

        Task {
            defer { isRewriting = false }

            do {
                let source = try await PasteboardAccess.readString()

                if source == lastResult {
                    HUDWindowController.shared.showHint("Already rewrote this. Copy new text first.")
                    return
                }

                let provider = Preferences.provider(from: .standard)
                let intent = Preferences.intent(from: .standard)
                let ollamaModel = Preferences.ollamaModel(from: .standard)

                let output = try await RewriteRunner.rewrite(
                    provider: provider,
                    intent: intent,
                    text: source,
                    ollamaModel: ollamaModel
                )

                guard output != source else {
                    HUDWindowController.shared.showHint("Looks good already — no changes needed.")
                    return
                }

                lastOriginal = source
                lastResult = output
                PasteboardAccess.writeString(output)
                HUDWindowController.shared.showResult(
                    original: source,
                    revised: output,
                    intent: intent
                )
            } catch let error as PasteboardAccess.ReadError {
                var message = error.localizedDescription
                if error == .accessDenied {
                    message += " Open Settings to change this."
                    PasteboardAccess.openPrivacySettings()
                }
                HUDWindowController.shared.showHint(message)
            } catch {
                HUDWindowController.shared.showHint(error.localizedDescription)
            }
        }
    }

    /// Restores the pre-rewrite text to the clipboard.
    func undo() {
        guard let lastOriginal else { return }
        PasteboardAccess.writeString(lastOriginal)
        lastResult = lastOriginal
        self.lastOriginal = nil
    }
}
