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
        hotkey.onHotKey = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.rewriteSelection()
            }
        }
        hotkey.register(shortcut)
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
        hotkey.register(newShortcut)
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
            let element = Self.focusedElement(),
            let selectedText = Self.selectedText(of: element),
            !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            DebugLog.log("rewrite: no focused element with a text selection")
            flash(systemImage: "text.cursor", message: "Select some text first")
            return
        }

        DebugLog.log("rewrite start: \(selectedText.count) chars selected")
        isWorking = true
        defer { isWorking = false }

        let anchor = Self.selectionAnchor(of: element) ?? Self.mouseAnchor()
        overlay.showStatus(
            systemImage: "sparkles", message: "Rewriting…",
            atTopLeftPoint: anchor, from: .rewrite
        )

        do {
            let output = try await RewriteRunner.rewrite(
                provider: Preferences.provider(from: defaults),
                intent: Preferences.intent(from: defaults),
                text: selectedText,
                ollamaModel: Preferences.ollamaModel(from: defaults)
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
        overlay.showStatus(
            systemImage: systemImage, message: message,
            atTopLeftPoint: Self.mouseAnchor(), from: .rewrite
        )
        Task { [overlay] in
            try? await Task.sleep(for: .seconds(2.5))
            overlay.hide(from: .rewrite)
        }
    }

    private static func focusedElement() -> AXUIElement? {
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

    private static func selectedText(of element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &selectedValue
            ) == .success
        else { return nil }
        return selectedValue as? String
    }

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

        var anchorRange = CFRange(location: selection.location, length: 0)
        guard let anchorRangeValue = AXValueCreate(.cfRange, &anchorRange) else { return nil }

        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                anchorRangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return CGPoint(x: rect.minX, y: rect.maxY + 6)
    }

    private static func mouseAnchor() -> CGPoint {
        SuggestionOverlayController.mouseTopLeftPoint()
    }
}
