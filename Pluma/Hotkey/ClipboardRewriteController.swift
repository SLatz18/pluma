import AppKit
import Foundation

/// The sandbox-legal universal flow (issue #12): the writer copies text, presses
/// the hotkey, pluma rewrites the clipboard in place, and they paste.
///
/// This is the second tier of issue #11's two-tier design. The first tier
/// (`SelectionRewriteController`) reads and writes the selection directly through
/// Accessibility, which is better when it works but fails in canvas-drawn and
/// Electron apps: Google Docs, Discord, some Chromium surfaces. Nothing here
/// touches Accessibility, so it works everywhere the writer can copy.
///
/// Ported from archive/pr-15-clipboard-flow. Two deliberate changes: the branch
/// registered its own parallel Carbon stack (`GlobalHotkey`,
/// `ClipboardHotkeyManager`), which duplicated `HotkeyManager` and would have
/// fought it for the same chord, so this uses the existing `.clipboardRewrite`
/// slot; and feedback goes through the AppKit status pill rather than the
/// branch's SwiftUI HUD, which is deferred (issues #13 and #16).
@MainActor
final class ClipboardRewriteController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var shortcutConflict: String?

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController
    private var debouncer = HotkeyDebouncer()

    /// The last text pluma wrote, so pressing again on an unchanged clipboard
    /// says so instead of paying for a second identical rewrite.
    private var lastResult: String?
    private var lastOriginal: String?

    init(
        defaults: UserDefaults = .standard,
        overlay: SuggestionOverlayController = SuggestionOverlayController()
    ) {
        self.defaults = defaults
        self.overlay = overlay
        shortcut = Preferences.clipboardShortcut(from: defaults)
        isEnabled = Preferences.clipboardFallbackEnabled(from: defaults)

        hotkey.onPress = { [weak self] slot in
            guard slot == .clipboardRewrite else { return }
            Task { @MainActor [weak self] in
                await self?.rewriteClipboard()
            }
        }
        if isEnabled {
            hotkey.register(shortcut, in: .clipboardRewrite)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        Preferences.setClipboardFallbackEnabled(enabled, to: defaults)
        if enabled {
            hotkey.register(shortcut, in: .clipboardRewrite)
        } else {
            hotkey.unregisterHotKey(.clipboardRewrite)
        }
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        guard let conflict = Self.conflict(for: newShortcut, defaults: defaults) else {
            shortcutConflict = nil
            shortcut = newShortcut
            Preferences.saveClipboardShortcut(newShortcut, to: defaults)
            if isEnabled {
                hotkey.register(newShortcut, in: .clipboardRewrite)
            }
            return
        }
        shortcutConflict = conflict
    }

    // Carbon refuses the same chord twice in one process, so a collision would
    // leave one feature silently dead rather than erroring. Pure function of its
    // arguments, so nonisolated: nothing here touches actor state.
    nonisolated static func conflict(
        for shortcut: GlobalShortcut,
        defaults: UserDefaults
    ) -> String? {
        if shortcut.conflicts(with: Preferences.globalShortcut(from: defaults)) {
            return "\(shortcut.display) is already used by Rewrite Selection."
        }
        if shortcut.conflicts(with: Preferences.dictationShortcut(from: defaults)) {
            return "\(shortcut.display) is already used by Dictation."
        }
        return nil
    }

    private func rewriteClipboard() async {
        // Carbon can deliver a held chord repeatedly; without this a long press
        // queues several rewrites of the same clipboard.
        guard debouncer.shouldFire() else { return }
        guard !isWorking else { return }
        DebugLog.log("clipboard hotkey fired")

        isWorking = true
        defer { isWorking = false }

        let source: String
        do {
            source = try await PasteboardAccess.readString()
        } catch let error as PasteboardAccess.ReadError {
            DebugLog.log("clipboard read failed: \(error)", at: .quiet)
            if error == .accessDenied {
                PasteboardAccess.openPrivacySettings()
            }
            flash(systemImage: "clipboard", message: error.localizedDescription)
            return
        } catch {
            flash(systemImage: "clipboard", message: error.localizedDescription)
            return
        }

        if source == lastResult {
            flash(
                systemImage: "checkmark.circle",
                message: "Already rewritten. Copy new text first.",
                tone: .neutral
            )
            return
        }

        let chain = Preferences.chain(from: defaults)
        guard !chain.isEmpty else {
            flash(systemImage: "slider.horizontal.3", message: "Pick at least one action first")
            return
        }

        // Same envelope treatment as the Service path, so the writer's
        // indentation and trailing newlines survive the round trip (#36).
        guard let envelope = TextEnvelope(source) else {
            flash(systemImage: "text.cursor", message: "Copy some text first")
            return
        }

        do {
            let rewritten = try await RewriteRunner.rewriteChain(
                provider: Preferences.provider(from: defaults),
                steps: chain,
                text: envelope.body,
                ollamaModel: Preferences.ollamaModel(from: defaults)
            )
            let output = try envelope.replacingBody(with: rewritten)

            guard output != source else {
                flash(
                    systemImage: "checkmark.circle",
                    message: "Looks good already",
                    tone: .neutral
                )
                return
            }

            lastOriginal = source
            lastResult = output
            PasteboardAccess.writeString(output)
            flash(systemImage: "doc.on.clipboard", message: "Rewritten. Press ⌘V", tone: .accent)
        } catch {
            DebugLog.log("clipboard rewrite failed: \(error.localizedDescription)", at: .quiet)
            flash(systemImage: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    /// Puts the pre-rewrite text back on the clipboard.
    func undo() {
        guard let lastOriginal else { return }
        PasteboardAccess.writeString(lastOriginal)
        // Point lastResult at the restored text so an immediate re-press is not
        // treated as a fresh clipboard.
        lastResult = lastOriginal
        self.lastOriginal = nil
        flash(systemImage: "arrow.uturn.backward", message: "Original restored", tone: .neutral)
    }

    private func flash(
        systemImage: String,
        message: String,
        tone: OverlayTone = .warning
    ) {
        overlay.flash(
            systemImage: systemImage, message: message, tone: tone,
            atTopLeftPoint: SuggestionOverlayController.mouseTopLeftPoint(), from: .rewrite
        )
    }
}
