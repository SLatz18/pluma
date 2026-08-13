import AppKit

enum GhostStyle: Equatable {
    case suggestion, dictation
}

// A breathing mark that says "live". Shared by the pill and the ghost text.
// It animates opacity only — never a colour — so a light/dark switch mid-pulse
// needs no CGColor bookkeeping.
@MainActor
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
//
// The text is laid out and drawn through this view's own layout manager rather
// than handed to an NSTextField. A field cannot say where its glyphs will land —
// its alignment rect is inset from its frame and its cell insets the text again,
// which put the first glyph several points right of the caret. Asking the font
// for a baseline instead was no better: the answer disagreed with where drawing
// actually placed it, by five points. Measuring and drawing from one layout
// manager is what makes them agree, and agreement is the whole feature — a
// mid-word completion has to sit flush against the half-typed word.
final class GhostTextView: NSView {
    private let dot = NSImageView()

    private let storage = NSTextStorage()
    private let textLayout = NSLayoutManager()
    private let container = NSTextContainer()

    private var hint = NSAttributedString()
    private var font: NSFont = .systemFont(ofSize: 13)
    private var style: GhostStyle = .suggestion

    // Between the text and the ⇥ hint, or between the recording dot and the
    // transcript. Never before the text in the suggestion look: that space is the
    // sentence's to give.
    private static let companionGap: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // The default 5 pt of line-fragment padding is exactly the kind of hidden
        // inset this view exists to avoid.
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 1
        textLayout.addTextContainer(container)
        storage.addLayoutManager(textLayout)

        // Dictation's feature tint from the design system, so the dot at the
        // caret and the mic in the pill say "dictation" in the same colour.
        dot.contentTintColor = DS.FeatureColor.dictation.nsColor
        dot.imageScaling = .scaleNone
        dot.isHidden = true
        addSubview(dot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Drawing in top-left origin coordinates keeps the arithmetic here in the
    // same orientation as the caret rects it has to match.
    override var isFlipped: Bool { true }

    // Distance from this view's top edge to the text baseline, so the panel can
    // be placed such that the ghost text sits on the caret line's own baseline.
    // Comes from the same layout manager that draws, so it cannot drift from it.
    var baselineOffsetFromTop: CGFloat {
        guard storage.length > 0 else { return font.ascender }
        textLayout.ensureLayout(for: container)
        let fragment = textLayout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return fragment.minY + textLayout.location(forGlyphAt: 0).y
    }

    // The height of one laid-out line, so the caller can tell how much of the
    // field's line box is padding rather than glyph.
    var lineHeight: CGFloat {
        guard storage.length > 0 else {
            return NSLayoutManager().defaultLineHeight(for: font)
        }
        textLayout.ensureLayout(for: container)
        return textLayout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    }

    // Where the glyphs begin, relative to the leading edge. Zero for the
    // suggestion look — that is the point of drawing this by hand. Dictation
    // leads with the pulsing dot, and the dot is what belongs at the caret.
    var textInsetFromLeading: CGFloat {
        style == .dictation ? dotSide + Self.companionGap : 0
    }

    // `maxWidth` is the room between the caret and the right edge of the field.
    // The text truncates into it; the view is never moved to make it fit.
    func show(text: String, style: GhostStyle, font: NSFont, maxWidth: CGFloat) {
        self.style = style
        self.font = font
        self.maxWidth = maxWidth

        let paragraph = NSMutableParagraphStyle()
        switch style {
        case .suggestion:
            RecordingPulse.stop(on: dot)
            dot.isHidden = true
            paragraph.lineBreakMode = .byTruncatingTail
            hint = NSAttributedString(
                string: "⇥",
                attributes: [
                    .font: NSFont.systemFont(ofSize: max(9, font.pointSize - 2), weight: .medium),
                    // Autocomplete's tint, faded almost to the quaternary
                    // weight it replaced: still a whisper, but the same
                    // indigo whisper the feature uses everywhere else.
                    .foregroundColor: DS.FeatureColor.autocomplete.nsColor
                        .withAlphaComponent(0.45)
                ]
            )
        case .dictation:
            dot.isHidden = false
            dot.image = NSImage(
                systemSymbolName: "circle.fill", accessibilityDescription: "Recording"
            )?.withSymbolConfiguration(.init(pointSize: dotSide, weight: .bold))
            RecordingPulse.start(on: dot)
            // Volatile results are revised as more audio arrives, so keep the
            // tail — the newest words — visible rather than the beginning.
            paragraph.lineBreakMode = .byTruncatingHead
            hint = NSAttributedString()
        }

        container.size = NSSize(width: textBudget, height: .greatestFiniteMagnitude)
        storage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph
                ]
            )
        )
        textLayout.ensureLayout(for: container)

        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    private var maxWidth: CGFloat = 200

    private var dotSide: CGFloat {
        max(5, (font.pointSize * 0.45).rounded())
    }

    private var companionWidth: CGFloat {
        switch style {
        case .suggestion: hint.size().width + Self.companionGap
        case .dictation: dotSide + Self.companionGap
        }
    }

    // The budget covers the whole view, so the dot or the hint comes out of it
    // before the text gets its share.
    private var textBudget: CGFloat {
        max(40, maxWidth - companionWidth)
    }

    override var intrinsicContentSize: NSSize {
        guard storage.length > 0 else { return NSSize(width: companionWidth, height: lineHeight) }
        textLayout.ensureLayout(for: container)
        let used = textLayout.usedRect(for: container)
        return NSSize(
            width: (used.width + companionWidth).rounded(.up),
            height: max(used.height, dotSide).rounded(.up)
        )
    }

    // The panel sizes itself from this. Without Auto Layout constraints to solve,
    // the inherited implementation has nothing to go on and answers zero, which
    // shows up as ghost text that is present in the log and invisible on screen.
    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        dot.frame = NSRect(
            x: 0,
            y: (baselineOffsetFromTop - dotSide / 2 - dotSide / 4).rounded(),
            width: dotSide,
            height: dotSide
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard storage.length > 0 else { return }
        let range = textLayout.glyphRange(for: container)
        // The line fragment's own origin is already accounted for by drawGlyphs,
        // so the text lands with its first glyph at exactly this point.
        textLayout.drawGlyphs(forGlyphRange: range, at: NSPoint(x: textInsetFromLeading, y: 0))

        guard style == .suggestion, hint.length > 0 else { return }
        let hintSize = hint.size()
        let hintFont = hint.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        // Sits on the text's baseline rather than centred, so it reads as part of
        // the same line.
        let hintTop = baselineOffsetFromTop - (hintFont?.ascender ?? hintSize.height)
        hint.draw(
            with: NSRect(
                x: bounds.width - hintSize.width,
                y: hintTop,
                width: hintSize.width,
                height: hintSize.height
            ),
            options: [.usesLineFragmentOrigin]
        )
    }
}
