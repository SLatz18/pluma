import AppKit

/// The overlay's one hook into developer mode. A protocol rather than a stored
/// closure so nothing has to be converted across actor isolation, and so the
/// production path is a single `nil` check on a weak reference.
@MainActor
protocol GhostTracing: AnyObject {
    func show(caret: CaretGeometry, ghostFrame: NSRect?)
}

// Draws where the app *thinks* the caret is, so a misplaced ghost text becomes
// something you can see rather than something you infer from numbers.
//
// Its own panel, deliberately not the shared overlay: that one shows a single
// presentation at a time and would fight with the very ghost text this is meant
// to measure.
@MainActor
final class CaretTracePanel: GhostTracing {
    private let panel: NSPanel
    private let view = TraceView()

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the ghost text, so the boxes are never hidden by what they
        // are measuring.
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
        ]
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    /// `ghostFrame` is in Cocoa screen coordinates (it comes straight from the
    /// overlay panel's own frame); the caret rect is in AX coordinates. Both are
    /// converted to one space here.
    func show(caret: CaretGeometry, ghostFrame: NSRect?) {
        guard let primary = NSScreen.screens.first else { return }

        let caretCocoa = NSRect(
            x: caret.rect.minX,
            y: primary.frame.height - caret.rect.maxY,
            width: max(caret.rect.width, 1),
            height: caret.rect.height
        )

        // Cover both boxes with a little slack for the outlines and label.
        var bounds = caretCocoa
        if let ghostFrame {
            bounds = bounds.union(ghostFrame)
        }
        let frame = bounds.insetBy(dx: -60, dy: -30)

        panel.setFrame(frame, display: false)
        view.caretRect = caretCocoa.offsetBy(dx: -frame.minX, dy: -frame.minY)
        view.ghostRect = ghostFrame?.offsetBy(dx: -frame.minX, dy: -frame.minY)
        view.caretSource = caret.source
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private final class TraceView: NSView {
        var caretRect: NSRect = .zero
        var ghostRect: NSRect?
        var caretSource: CaretSource = .exactCaret

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setStroke()
            let caretPath = NSBezierPath(rect: caretRect.insetBy(dx: -1, dy: -1))
            caretPath.lineWidth = 1
            caretPath.stroke()

            if let ghostRect {
                NSColor.systemBlue.setStroke()
                let ghostPath = NSBezierPath(rect: ghostRect)
                ghostPath.lineWidth = 1
                ghostPath.setLineDash([3, 2], count: 2, phase: 0)
                ghostPath.stroke()
            }

            // A caption, because red and blue alone don't say which probe won.
            let caption = "caret · \(caretSource.title)" + (ghostRect == nil ? "" : "  |  ghost")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.systemRed
            ]
            (caption as NSString).draw(
                at: NSPoint(x: caretRect.minX, y: caretRect.maxY + 3),
                withAttributes: attributes
            )
        }
    }
}
