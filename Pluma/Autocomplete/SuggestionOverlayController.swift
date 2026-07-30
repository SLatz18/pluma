import AppKit

// Pure-AppKit pill: the previous SwiftUI hosting view re-entered
// setNeedsUpdateConstraints during display-cycle layout and crashed the app
// (twice), so the overlay avoids a SwiftUI graph entirely.
//
// This is the chip the app wears when it is talking about itself — progress,
// errors, permission nags — and the fallback for the cases where ghost text
// cannot be drawn honestly. Text the user is about to accept goes to
// GhostTextView instead.
// Shaped after the completion chip macOS itself puts under the caret when it
// wants to fix a word: a capsule, a light fill, a soft shadow, the word in
// ordinary text colour, and a hairline before the trailing glyph. People have
// been dismissing that chip for years, so it needs no explaining.
//
// It departs from the system's in one place, deliberately. macOS puts an ✕
// there, because its chip applies itself unless you refuse. This one is offered
// rather than applied, so the trailing glyph is ⇥ — the key that takes it.
private final class OverlayPillRenderer: NSVisualEffectView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "⇥")
    private let divider = NSView()
    private let stack = NSStackView()

    // The system chip's own proportions: roomy sides, tight top and bottom.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: DS.Overlay.textSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.preferredMaxLayoutWidth = DS.Overlay.maximumTextWidth

        hintLabel.font = .systemFont(ofSize: DS.Overlay.textSize - 1, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor

        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([divider.widthAnchor.constraint(equalToConstant: 1)])

        applyDynamicColors()

        iconView.contentTintColor = .secondaryLabelColor

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = DS.Overlay.itemSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: DS.Overlay.verticalInset, left: DS.Overlay.horizontalInset,
            bottom: DS.Overlay.verticalInset, right: DS.Overlay.horizontalInset
        )
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(hintLabel)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The hairline runs the text's height, not the capsule's, so it
            // stops short of the rounded ends.
            divider.heightAnchor.constraint(equalTo: label.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // A capsule at any height, so the shape survives the text growing with the
    // field's own font.
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    // CGColors are resolved snapshots: without this, a dark↔light switch while
    // the pill is up leaves the border and hairline painted for the old mode.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDynamicColors()
    }

    private func applyDynamicColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    // One size, one weight, one width, one colour for every pill the app shows.
    // Suggesting, dictating, and reporting a problem are different messages, but
    // they arrive in the same place wearing the same chip; a size that shifted
    // between them would read as three components rather than one.
    private func applySharedTypography(lineBreak: NSLineBreakMode = .byTruncatingTail) {
        label.font = .systemFont(ofSize: DS.Overlay.textSize)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = lineBreak
        label.preferredMaxLayoutWidth = DS.Overlay.maximumTextWidth
        hintLabel.font = .systemFont(ofSize: DS.Overlay.textSize - 1)
        iconView.image = iconView.image?.withSymbolConfiguration(
            .init(pointSize: DS.Overlay.textSize - 1, weight: .semibold)
        )
    }

    func showSuggestion(_ text: String) {
        RecordingPulse.stop(on: iconView)
        iconView.isHidden = true
        divider.isHidden = false
        hintLabel.isHidden = false
        applySharedTypography()
        label.stringValue = text
    }

    func showStatus(
        systemImage: String,
        message: String,
        tone: OverlayTone,
        pulses: Bool
    ) {
        iconView.isHidden = false
        iconView.contentTintColor = tone.color
        iconView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: DS.Overlay.textSize - 1, weight: .semibold))
        if pulses {
            RecordingPulse.start(on: iconView)
        } else {
            RecordingPulse.stop(on: iconView)
        }
        divider.isHidden = true
        hintLabel.isHidden = true
        applySharedTypography()
        label.stringValue = message
    }

    func showDictation(transcript: String) {
        iconView.isHidden = false
        iconView.contentTintColor = .systemRed
        iconView.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")?
            .withSymbolConfiguration(.init(pointSize: DS.Overlay.textSize - 1, weight: .semibold))
        RecordingPulse.start(on: iconView)
        divider.isHidden = true
        hintLabel.isHidden = true
        // Volatile results get revised as more audio arrives, so keep the tail —
        // the newest words — visible rather than the beginning.
        applySharedTypography(lineBreak: transcript.isEmpty ? .byTruncatingTail : .byTruncatingHead)
        label.textColor = transcript.isEmpty ? .secondaryLabelColor : .labelColor
        label.stringValue = transcript.isEmpty ? "Listening…" : transcript
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

    private enum Placement {
        case topLeft(CGPoint)
        case ghost(CaretGeometry)
    }

    private var panel: NSPanel?
    private var pill: OverlayPillRenderer?
    private var ghost: GhostTextView?
    private var pendingContent: NSView?
    private var pendingPlacement: Placement?
    private var currentOwner: Owner?
    private var animatesNextFrameChange = false
    // Bumped by every show and every hide so a fade-out's deferred orderOut
    // can never kill a presentation that arrived after the hide started.
    private var hideGeneration = 0

    var isVisible: Bool { panel?.isVisible ?? false }

    // Who the pill currently belongs to, so the arbitration between an ambient
    // suggestion and a held-key recording can be tested without a screen.
    var owner: Owner? { currentOwner }

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

    func show(_ presentation: OverlayPresentation, from owner: Owner) {
        // Autocomplete is the only ambient speaker here — it offers things
        // nobody asked for. Dictation, selection rewrite, and the developer
        // trace all run because the writer is holding a key or pressed one, so
        // they take the pill and keep it. Without this the two simply raced:
        // hold the dictation shortcut and the next completion would land on top
        // of "Listening…", then the transcript would land on top of that.
        // Ownership decides this, not visibility: presentation is deferred a run
        // loop turn, so a completion arriving in the same turn as the recording
        // would find the panel still not visible and take it anyway.
        if owner == .autocomplete, let currentOwner, currentOwner != .autocomplete {
            return
        }
        let previousOwner = currentOwner
        currentOwner = owner
        ensurePanel()
        guard let pill, let ghost else { return }
        // A handover is the one time the pill's own size is worth animating: the
        // writer sees the suggestion give way to the recording rather than one
        // pill blinking out and another appearing in its place.
        animatesNextFrameChange = previousOwner != nil && previousOwner != owner

        switch presentation.content {
        case let .ghost(text, caret, style, fieldFrame):
            let font = Self.ghostFont(for: caret)
            let budget = GhostTextGeometry.widthBudget(
                caretMaxX: caret.rect.maxX,
                fieldMaxX: fieldFrame?.maxX,
                screenMaxX: Self.screenMaxX(forCaretRect: caret.rect)
            )
            DebugLog.log(
                "ghost \(style) at \(FocusedFieldTracker.describe(caret.rect)) "
                    + "via \(caret.source.title), font \(font.fontName) "
                    + "\(Int(font.pointSize))pt (\(caret.font == nil ? "inferred" : "reported")), "
                    + "budget \(Int(budget))pt",
                at: .verbose
            )
            ghost.show(text: text, style: style, font: font, maxWidth: budget)
            present(ghost, placement: .ghost(caret))

        case let .suggestion(text):
            guard let anchor = presentation.anchor else { return }
            pill.showSuggestion(text)
            present(pill, placement: .topLeft(anchor))

        case let .dictation(transcript):
            guard let anchor = presentation.anchor else { return }
            pill.showDictation(transcript: transcript)
            present(pill, placement: .topLeft(anchor))

        case let .status(systemImage, message, tone, pulses):
            guard let anchor = presentation.anchor else { return }
            pill.showStatus(
                systemImage: systemImage,
                message: message,
                tone: tone,
                pulses: pulses
            )
            present(pill, placement: .topLeft(anchor))
        }
    }

    // A status that dismisses itself — for permission nags, mis-presses, and
    // failures. The owner-scoped hide means a flash that fires just before a
    // newer presentation can't hide it.
    func flash(
        systemImage: String,
        message: String,
        tone: OverlayTone = .warning,
        atTopLeftPoint point: CGPoint,
        from owner: Owner
    ) {
        show(
            .status(systemImage: systemImage, message: message, tone: tone, anchor: point),
            from: owner
        )
        Task { [weak self] in
            try? await Task.sleep(for: DS.Motion.flash)
            self?.hide(from: owner)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let pill = OverlayPillRenderer(frame: .zero)
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
            // The chip is a thing sitting above the document and casts a shadow
            // like the system's own. Ghost text is pretending to be the document,
            // and a shadow would give it away instantly.
            panel.hasShadow = content === self.pill
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize

            // A handover animates its whole frame, so the size must not be
            // applied up front — that is the change the writer is meant to see.
            let handover = animatesNextFrameChange && panel.isVisible && !reduceMotion
            animatesNextFrameChange = false
            if !handover {
                panel.setContentSize(fitting)
                // A second pass: the baseline offset below is only meaningful
                // once the label has been laid out at its final width.
                content.layoutSubtreeIfNeeded()
            }

            let target: CGPoint
            switch placement {
            case let .topLeft(point):
                target = clampedOrigin(forTopLeftPoint: point, panelSize: fitting)
            case let .ghost(caret):
                let ghost = content as? GhostTextView
                let offset = ghost?.baselineOffsetFromTop ?? 0
                let caretBaseline = GhostTextGeometry.baselineY(
                    forCaretRect: caret.rect,
                    lineHeight: ghost?.lineHeight,
                    baselineOffset: offset
                )
                let topLeft = CGPoint(
                    x: caret.rect.maxX + GhostTextGeometry.caretGap
                        - (ghost?.textInsetFromLeading ?? 0),
                    y: caretBaseline - offset
                )
                target = ghostOrigin(forTopLeftPoint: topLeft, panelSize: fitting)
                ghostTrace?.show(caret: caret, ghostFrame: NSRect(origin: target, size: fitting))
            }

            // The suggestion giving way to the recording: one pill resizing in
            // place, rather than a blink out and a new one appearing.
            if handover {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = DS.Motion.present
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(
                        NSRect(origin: target, size: fitting), display: true
                    )
                }
                return
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
            panel.setFrameOrigin(CGPoint(x: target.x, y: target.y - DS.Motion.rise))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DS.Motion.present
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
                context.duration = DS.Motion.dismiss
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.hideGeneration == generation else { return }
                    self.panel?.orderOut(nil)
                    self.panel?.alphaValue = 1
                }
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
        let visible = screen.visibleFrame.insetBy(
            dx: DS.Overlay.screenInset,
            dy: DS.Overlay.screenInset
        )
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

    // Match the field's own typeface and size when Accessibility named them, so
    // the ghost text continues the sentence in the same hand it is written in.
    // Falling back to the system font at an inferred size is a visible tell:
    // Helvetica at 12 pt against San Francisco at 11 pt reads as a different
    // piece of text sitting nearby, which is exactly the illusion to avoid.
    private static func ghostFont(for caret: CaretGeometry) -> NSFont {
        let size = GhostTextGeometry.fontSize(
            forCaretHeight: caret.rect.height, reportedSize: caret.font?.size
        )
        if let name = caret.font?.name, let matched = NSFont(name: name, size: size) {
            return matched
        }
        return .systemFont(ofSize: size)
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
