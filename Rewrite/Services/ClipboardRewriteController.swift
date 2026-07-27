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
        let pasteboard = NSPasteboard.general

        guard
            let source = pasteboard.string(forType: .string),
            !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            HUDWindowController.shared.showHint("Copy some text first, then press the hotkey.")
            return
        }

        // Clipboard still holds our previous result — the user probably
        // pressed the hotkey again without copying new text.
        if source == lastResult {
            HUDWindowController.shared.showHint("Already rewrote this. Copy new text first.")
            return
        }

        guard !isRewriting else { return }
        isRewriting = true

        let provider = Preferences.provider(from: .standard)
        let intent = Preferences.intent(from: .standard)
        let ollamaModel = Preferences.ollamaModel(from: .standard)

        Task {
            defer { isRewriting = false }
            do {
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
                pasteboard.clearContents()
                pasteboard.setString(output, forType: .string)
                HUDWindowController.shared.showResult(
                    original: source,
                    revised: output,
                    intent: intent
                )
            } catch {
                HUDWindowController.shared.showHint(error.localizedDescription)
            }
        }
    }

    /// Restores the pre-rewrite text to the clipboard.
    func undo() {
        guard let lastOriginal else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastOriginal, forType: .string)
        lastResult = lastOriginal
        self.lastOriginal = nil
    }
}
