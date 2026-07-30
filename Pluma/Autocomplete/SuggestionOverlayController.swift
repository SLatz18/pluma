import AppKit

// Pure-AppKit pill: the previous SwiftUI hosting view re-entered
// setNeedsUpdateConstraints during display-cycle layout and crashed the app
// (twice), so the overlay avoids a SwiftUI graph entirely.
//
// This is the chip the app wears when it is talking about itself — progress,
// errors, permission nags — and the fallback for the cases where ghost text
// cannot be drawn honestly. Text the user is about to accept goes to
// GhostTextView instead.
private final class PillView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "⇥")
    private let hintBezel = NSView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.preferredMaxLayoutWidth = 500

        hintLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        hintLabel.textColor = .tertiaryLabelColor
        hintBezel.wantsLayer = true
        hintBezel.layer?.cornerRadius = 3
        applyDynamicColors()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintBezel.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: hintBezel.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: hintBezel.centerYAnchor),
            hintBezel.widthAnchor.constraint(equalTo: hintLabel.widthAnchor, constant: 8),
            hintBezel.heightAnchor.constraint(equalTo: hintLabel.heightAnchor, constant: 2)
        ])

        iconView.contentTintColor = .secondaryLabelColor

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(hintBezel)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // CGColors are resolved snapshots: without this, a dark↔light switch while
    // the pill is up leaves the border and bezel painted for the old mode.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDynamicColors()
    }

    private func applyDynamicColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
            hintBezel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        }
    }

    func showSuggestion(_ text: String) {
        RecordingPulse.stop(on: iconView)
        iconView.isHidden = true
        hintBezel.isHidden = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = 500
        label.stringValue = text
    }

    func showStatus(systemImage: String, message: String) {
        RecordingPulse.stop(on: iconView)
        iconView.isHidden = false
        iconView.contentTintColor = .secondaryLabelColor
        let base = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        iconView.image = base?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        hintBezel.isHidden = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.preferredMaxLayoutWidth = 500
        label.stringValue = message
    }

    func showDictation(transcript: String) {
        iconView.isHidden = false
        iconView.contentTintColor = .systemRed
        let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
        iconView.image = base?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        RecordingPulse.start(on: iconView)
        hintBezel.isHidden = true
        if transcript.isEmpty {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 1
            label.stringValue = "Listening…"
        } else {
            // Volatile results get revised as more audio arrives, so keep the
            // tail visible rather than the beginning.
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.maximumNumberOfLines = 2
            label.stringValue = transcript
        }
        label.lineBreakMode = .byTruncatingHead
        label.preferredMaxLayoutWidth = 320
    }
}

@MainActor
final class SuggestionOverlayController {
    // One panel is shared by autocomplete, selection rewrite, and dictation.
    // Shows always preempt (last writer wins), but a hide only lands if the
    // current presentation belongs to the caller — so a delayed hide (e.g. a
    // status flash's 2.5 s timer) can't kill a newer presentation.
    enum Owner {
        case autocomplete, rewrite, dictation, developer
    }

    // Set only while developer-mode caret tracing is on, so the trace panel can
    // draw where the ghost text actually landed next to where the caret was
    // reported. Nil in every normal run — one optional check per present.
    // Weak: the developer-mode object owns the panel, not the overlay.
    weak var ghostTrace: (any GhostTracing)?

    // Two looks, one panel. The dividing line is whose words these are: ghost
    // text is text that will land in the user's document, so it is drawn as if
    // it already had; everything else is the app speaking, and wears the chip.
    enum Presentation {
        case ghost(text: String, caret: CaretGeometry, style: GhostStyle, fieldFrame: CGRect?)
        case suggestionChip(text: String, anchor: CGPoint)
        case dictationChip(transcript: String, anchor: CGPoint)
        case status(systemImage: String, message: String, anchor: CGPoint)
    }

    private enum Placement {
        case topLeft(CGPoint)
        case ghost(CaretGeometry)
    }

    private var panel: NSPanel?
    private var pill: PillView?
    private var ghost: GhostTextView?
    private var pendingContent: NSView?
    private var pendingPlacement: Placement?
    private var currentOwner: Owner?
    // Bumped by every show and every hide so a fade-out's deferred orderOut
    // can never kill a presentation that arrived after the hide started.
    private var hideGeneration = 0

    var isVisible: Bool { panel?.isVisible ?? false }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // The last-resort anchor, and deliberately the only place the mouse is
    // used: it has no relationship to where text will land, so it is reserved
    // for messages that have no field to point at at all ("Click into a text
    // field first", "Rewrite needs Accessibility access").
    //
    // NSEvent.mouseLocation is Cocoa bottom-left-origin; AX/overlay coordinates
    // are top-left-origin on the primary display.
    static func mouseTopLeftPoint() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? mouse.y
        return CGPoint(x: mouse.x + 8, y: primaryHeight - mouse.y + 12)
    }

    func show(_ presentation: Presentation, from owner: Owner) {
        currentOwner = owner
        ensurePanel()
        guard let pill, let ghost else { return }

        switch presentation {
        case let .ghost(text, caret, style, fieldFrame):
            let font = NSFont.systemFont(
                ofSize: GhostTextGeometry.fontSize(forCaretHeight: caret.rect.height)
            )
            let budget = GhostTextGeometry.widthBudget(
                caretMaxX: caret.rect.maxX,
                fieldMaxX: fieldFrame?.maxX,
                screenMaxX: Self.screenMaxX(forCaretRect: caret.rect)
            )
            DebugLog.log(
                "ghost \(style) at \(FocusedFieldTracker.describe(caret.rect)) "
                    + "via \(caret.source.title), font \(Int(font.pointSize))pt, "
                    + "budget \(Int(budget))pt",
                at: .verbose
            )
            ghost.show(text: text, style: style, font: font, maxWidth: budget)
            present(ghost, placement: .ghost(caret))

        case let .suggestionChip(text, anchor):
            pill.showSuggestion(text)
            present(pill, placement: .topLeft(anchor))

        case let .dictationChip(transcript, anchor):
            pill.showDictation(transcript: transcript)
            present(pill, placement: .topLeft(anchor))

        case let .status(systemImage, message, anchor):
            pill.showStatus(systemImage: systemImage, message: message)
            present(pill, placement: .topLeft(anchor))
        }
    }

    // A status that dismisses itself — for permission nags, mis-presses, and
    // failures. The owner-scoped hide means a flash that fires just before a
    // newer presentation can't hide it.
    func flash(systemImage: String, message: String, atTopLeftPoint point: CGPoint, from owner: Owner) {
        show(.status(systemImage: systemImage, message: message, anchor: point), from: owner)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.hide(from: owner)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let pill = PillView(frame: .zero)
        let ghost = GhostTextView(frame: .zero)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
        ]
        panel.ignoresMouseEvents = true
        panel.contentView = pill
        self.panel = panel
        self.pill = pill
        self.ghost = ghost
    }

    // Deferred one run loop turn so window mutations never land inside an
    // in-flight display cycle. What to draw is parked on the controller rather
    // than captured, both to keep the closure's captures to `self` alone and
    // because a show that arrives first is meant to lose to a later one.
    private func present(_ content: NSView, placement: Placement) {
        pendingContent = content
        pendingPlacement = placement
        hideGeneration += 1
        DispatchQueue.main.async { [weak self] in
            guard
                let self, let panel,
                let content = pendingContent,
                let placement = pendingPlacement
            else { return }
            if panel.contentView !== content {
                panel.contentView = content
            }
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            panel.setContentSize(fitting)
            // A second pass: the baseline offset below is only meaningful once
            // the label has been laid out at its final width.
            content.layoutSubtreeIfNeeded()

            let target: CGPoint
            switch placement {
            case let .topLeft(point):
                target = clampedOrigin(forTopLeftPoint: point, panelSize: fitting)
            case let .ghost(caret):
                let offset = (content as? GhostTextView)?.baselineOffsetFromTop ?? 0
                let topLeft = CGPoint(
                    x: caret.rect.maxX + GhostTextGeometry.caretGap,
                    y: GhostTextGeometry.baselineY(forCaretRect: caret.rect) - offset
                )
                target = ghostOrigin(forTopLeftPoint: topLeft, panelSize: fitting)
                ghostTrace?.show(caret: caret, ghostFrame: NSRect(origin: target, size: fitting))
            }

            // Caret-tracking updates stay instant so the text never lags a
            // keystroke; only a fresh appearance earns the fade-and-rise.
            guard !panel.isVisible, !reduceMotion else {
                panel.alphaValue = 1
                panel.setFrameOrigin(target)
                panel.orderFrontRegardless()
                return
            }
            panel.alphaValue = 0
            panel.setFrameOrigin(CGPoint(x: target.x, y: target.y - 5))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        }
    }

    func hide() {
        currentOwner = nil
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel, panel.isVisible else { return }
            guard !reduceMotion else {
                panel.orderOut(nil)
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.hideGeneration == generation else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            })
        }
    }

    func hide(from owner: Owner) {
        guard currentOwner == owner else { return }
        hide()
    }

    // AX coordinates are top-left-origin relative to the primary display;
    // Cocoa window origins are bottom-left-origin on that same display. The
    // pill is kept fully inside the target screen's visible frame so a caret
    // at the screen edge never pushes it offscreen.
    private func clampedOrigin(forTopLeftPoint point: CGPoint, panelSize: NSSize) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        let cocoaPoint = CGPoint(x: point.x, y: primary.frame.height - point.y)
        let origin = CGPoint(x: cocoaPoint.x, y: cocoaPoint.y - panelSize.height)

        let screen = NSScreen.screens.first { NSPointInRect(cocoaPoint, $0.frame) } ?? primary
        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        return CGPoint(
            x: max(visible.minX, min(origin.x, max(visible.minX, visible.maxX - panelSize.width))),
            y: max(visible.minY, min(origin.y, max(visible.minY, visible.maxY - panelSize.height)))
        )
    }

    // Ghost text is clamped vertically but never horizontally: sliding it left
    // to keep it onscreen would park it in the middle of the user's sentence.
    // Overrun is prevented earlier instead, by the width budget the text was
    // truncated to.
    private func ghostOrigin(forTopLeftPoint point: CGPoint, panelSize: NSSize) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        let cocoaPoint = CGPoint(x: point.x, y: primary.frame.height - point.y)
        let origin = CGPoint(x: cocoaPoint.x, y: cocoaPoint.y - panelSize.height)

        let screen = NSScreen.screens.first { NSPointInRect(cocoaPoint, $0.frame) } ?? primary
        let visible = screen.visibleFrame
        return CGPoint(
            x: origin.x,
            y: max(visible.minY, min(origin.y, max(visible.minY, visible.maxY - panelSize.height)))
        )
    }

    // The right edge of the display the caret is on, in AX coordinates. Only y
    // differs between the two systems, so x carries over untouched.
    private static func screenMaxX(forCaretRect rect: CGRect) -> CGFloat {
        guard let primary = NSScreen.screens.first else { return rect.maxX }
        let cocoaPoint = CGPoint(x: rect.midX, y: primary.frame.height - rect.midY)
        let screen = NSScreen.screens.first { NSPointInRect(cocoaPoint, $0.frame) } ?? primary
        return screen.visibleFrame.maxX
    }
}
