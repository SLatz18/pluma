import AppKit
import SwiftUI

/// Presents the change-summary HUD (issue #13) as a floating,
/// non-activating panel. Focus always stays in the source app.
@MainActor
final class HUDWindowController {
    static let shared = HUDWindowController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showResult(original: String, revised: String, intent: RewriteIntent) {
        let view = RewriteHUDView(
            mode: .result(original: original, revised: revised, intent: intent),
            onUndo: { [weak self] in
                if ClipboardRewriteController.shared.undo() {
                    self?.dismiss()
                } else {
                    self?.showHint("The clipboard changed, so Rewrite left it alone.")
                }
            },
            onDone: { [weak self] in self?.dismiss() }
        )
        present(view, width: 380, autoDismissAfter: nil)
    }

    func showHint(_ message: String) {
        let view = RewriteHUDView(
            mode: .hint(message),
            onUndo: nil,
            onDone: { [weak self] in self?.dismiss() }
        )
        present(view, width: 320, autoDismissAfter: 3.5)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func present<Content: View>(
        _ view: Content,
        width: CGFloat,
        autoDismissAfter seconds: Double?
    ) {
        dismissTask?.cancel()

        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let availableHeight = (targetScreen?.visibleFrame.height ?? 800) - 24
        let size = NSSize(
            width: width,
            height: min(max(fitting.height, 60), availableHeight)
        )

        let panel = makePanel(size: size)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        positionTopRight(panel)
        panel.orderFrontRegardless()

        if let seconds {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        if let panel {
            panel.setContentSize(size)
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = targetScreen else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - 16,
            y: frame.maxY - panel.frame.height - 12
        )
        panel.setFrameOrigin(origin)
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
