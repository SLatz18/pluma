import AppKit

enum GhostStyle: Equatable {
    case suggestion, dictation
}

// A breathing red mark that says "live". Shared by the pill and the ghost text.
// It animates opacity only — never a colour — so a light/dark switch mid-pulse
// needs no CGColor bookkeeping.
enum RecordingPulse {
    private static let key = "recordingPulse"

    static func start(on view: NSView) {
        view.wantsLayer = true
        guard view.layer?.animation(forKey: key) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer?.add(pulse, forKey: key)
    }

    static func stop(on view: NSView) {
        view.layer?.removeAnimation(forKey: key)
        view.layer?.opacity = 1
    }
}

// Text the user is about to accept, drawn as if it were already in their
// document: grey, unstyled, on the caret's own line. Deliberately has no
// background, border, corner radius, or shadow — every one of those would give
// away that this is a window floating over the app.
//
// Pure AppKit for the same reason PillView is: a SwiftUI hosting view re-enters
// layout during the display cycle here and crashes.
final class GhostTextView: NSView {
    private let dot = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "⇥")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.maximumNumberOfLines = 1
        label.textColor = .secondaryLabelColor

        // Faint enough to read as a keyboard hint rather than part of the
        // sentence, but it replaces the old bezelled chip entirely.
        hint.textColor = .quaternaryLabelColor

        dot.contentTintColor = .systemRed
        dot.imageScaling = .scaleNone

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.addArrangedSubview(dot)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(hint)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The label must stay the tallest thing in the row: that is what
            // makes its top edge the view's top edge, which is the assumption
            // baselineOffsetFromTop rests on.
            dot.heightAnchor.constraint(lessThanOrEqualTo: label.heightAnchor),
            hint.heightAnchor.constraint(lessThanOrEqualTo: label.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Distance from this view's top edge to the text baseline, so the panel can
    // be placed such that the ghost text sits on the caret line's baseline
    // rather than merely near it. The label spans the full height (see the
    // constraints above), so its own offset is the view's. Read only after a
    // layout pass.
    var baselineOffsetFromTop: CGFloat {
        label.firstBaselineOffsetFromTop
    }

    // Distance from this view's leading edge to where the label's glyphs
    // actually begin. NSTextField's cell insets its text by a couple of points,
    // which nobody notices inside a chip and which reads as a gap when the text
    // is supposed to continue the writer's sentence from the caret.
    //
    // Only meaningful for the suggestion look. Dictation leads with the pulsing
    // dot, and that dot is what should sit at the caret.
    // Where the label's glyphs begin, relative to this view's leading edge.
    // NSTextField's alignment rect is inset from its frame, and Auto Layout pins
    // the alignment rect — so pinning the stack flush to this view still leaves
    // the text drawing a couple of points outside it. Measured rather than
    // assumed, because the inset is AppKit's to change.
    //
    // Zero for dictation: that look leads with the pulsing dot, and the dot is
    // what belongs at the caret.
    var textInsetFromLeading: CGFloat {
        guard dot.isHidden, let cell = label.cell else { return 0 }
        let titleX = cell.titleRect(forBounds: label.bounds).minX
        return label.convert(CGPoint(x: titleX, y: 0), to: self).x
    }

    // `maxWidth` is the room between the caret and the right edge of the field.
    // The text truncates into it; the view is never moved to make it fit.
    func show(text: String, style: GhostStyle, font: NSFont, maxWidth: CGFloat) {
        label.font = font

        switch style {
        case .suggestion:
            RecordingPulse.stop(on: dot)
            dot.isHidden = true
            hint.isHidden = false
            hint.font = .systemFont(ofSize: max(9, font.pointSize - 2), weight: .medium)
            label.lineBreakMode = .byTruncatingTail
        case .dictation:
            dot.isHidden = false
            hint.isHidden = true
            let dotSize = max(5, (font.pointSize * 0.45).rounded())
            dot.image = NSImage(
                systemSymbolName: "circle.fill", accessibilityDescription: "Recording"
            )?.withSymbolConfiguration(.init(pointSize: dotSize, weight: .bold))
            RecordingPulse.start(on: dot)
            // Volatile results are revised as more audio arrives, so keep the
            // tail — the newest words — visible rather than the beginning.
            label.lineBreakMode = .byTruncatingHead
        }

        // The budget covers the whole view, so the dot or the hint has to come
        // out of it before the label gets its share.
        let companion: NSView = style == .suggestion ? hint : dot
        let reserved = companion.fittingSize.width + stack.spacing
        label.preferredMaxLayoutWidth = max(40, maxWidth - reserved)
        label.stringValue = text
    }
}
