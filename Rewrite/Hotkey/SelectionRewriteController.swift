import AppKit
import ApplicationServices

@MainActor
final class SelectionRewriteController: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var isWorking = false
    @Published private(set) var shortcutConflict: String?

    private let defaults: UserDefaults
    private let hotkey = HotkeyManager()
    private let overlay: SuggestionOverlayController

    init(defaults: UserDefaults = .standard, overlay: SuggestionOverlayController = SuggestionOverlayController()) {
        self.defaults = defaults
        self.overlay = overlay
        shortcut = Preferences.globalShortcut(from: defaults)
        hotkey.onPress = { [weak self] slot in
            guard slot == .rewriteSelection else { return }
            Task { @MainActor [weak self] in
                await self?.rewriteSelection()
            }
        }
        hotkey.register(shortcut, in: .rewriteSelection)
    }

    func recordShortcut(_ newShortcut: GlobalShortcut) {
        let dictationShortcut = Preferences.dictationShortcut(from: defaults)
        guard !newShortcut.conflicts(with: dictationShortcut) else {
            shortcutConflict = "\(newShortcut.display) is already used by Dictation."
            return
        }
        shortcutConflict = nil
        shortcut = newShortcut
        Preferences.saveGlobalShortcut(newShortcut, to: defaults)
        hotkey.register(newShortcut, in: .rewriteSelection)
    }

    private func rewriteSelection() async {
        guard !isWorking else { return }
        DebugLog.log("hotkey fired")

        guard AccessibilityPermission.shared.isTrusted else {
            DebugLog.log("rewrite blocked: not trusted")
            flash(systemImage: "hand.raised", message: "Rewrite needs Accessibility access")
            return
        }

        guard
            let element = AXFocus.focusedElement(),
            let selectedText = Self.selectedText(of: element),
            !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            DebugLog.log("rewrite: no focused element with a text selection")
            flash(systemImage: "text.cursor", message: "Select some text first")
            return
        }

        let chain = Preferences.chain(from: defaults)
        guard !chain.isEmpty else {
            flash(systemImage: "sparkles", message: "Pick a recipe on the Rewrite page first")
            return
        }

        DebugLog.log("rewrite start: \(selectedText.count) chars selected, chain \(chain.count) steps")
        isWorking = true
        defer { isWorking = false }

        let anchor = Self.selectionAnchor(of: element) ?? Self.mouseAnchor()
        overlay.show(
            .status(systemImage: "sparkles", message: "Rewriting…", anchor: anchor),
            from: .rewrite
        )

        do {
            let output = try await RewriteRunner.rewriteChain(
                provider: Preferences.provider(from: defaults),
                steps: chain,
                text: selectedText,
                ollamaModel: Preferences.ollamaModel(from: defaults),
                onProgress: { [overlay] progress in
                    guard case .starting(let step, let of, let intent) = progress, of > 1 else { return }
                    overlay.show(
                        .status(
                            systemImage: "sparkles",
                            message: "Rewriting \(step) of \(of) — \(intent.title)…",
                            anchor: anchor
                        ),
                        from: .rewrite
                    )
                }
            )
            if await AXTextInsertion.insert(output, into: element) {
                DebugLog.log("rewrite inserted OK")
                overlay.hide(from: .rewrite)
            } else {
                DebugLog.log("rewrite insertion failed")
                flash(systemImage: "exclamationmark.triangle", message: "This field rejected the edit")
            }
        } catch {
            DebugLog.log("rewrite failed: \(error.localizedDescription)")
            flash(systemImage: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    private func flash(systemImage: String, message: String) {
        overlay.flash(
            systemImage: systemImage, message: message,
            atTopLeftPoint: Self.mouseAnchor(), from: .rewrite
        )
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &selectedValue
            ) == .success
        else { return nil }
        return selectedValue as? String
    }

    // Just below the start of the selection, so the progress chip never covers
    // the text being rewritten.
    private static func selectionAnchor(of element: AXUIElement) -> CGPoint? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return nil }

        guard
            let caret = FocusedFieldTracker.caretGeometry(for: element, location: selection.location)
        else { return FocusedFieldTracker.fieldEdgeAnchor(for: element) }
        return CGPoint(x: caret.rect.minX, y: caret.rect.maxY + 6)
    }

    private static func mouseAnchor() -> CGPoint {
        SuggestionOverlayController.mouseTopLeftPoint()
    }
}
