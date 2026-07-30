import CoreGraphics
import Foundation

// Whether a field can take ghost text at all. Ghost text is drawn to the right
// of the caret, so it needs nothing to its right to cover up and a line that
// runs that way; anything else falls back to the chip.
//
// Read from the field's text once per snapshot rather than per repaint, since
// it costs an Accessibility round trip.
struct GhostTextEligibility: Equatable {
    let caretAtEndOfLine: Bool
    let isRightToLeft: Bool

    static let unknown = GhostTextEligibility(caretAtEndOfLine: false, isRightToLeft: false)

    // End of *line*, not end of text. Nothing to the right on this line is the
    // whole requirement, and insisting on the last character of the document
    // refused ghost text in most real editors: anything with a trailing newline,
    // or a caret partway down a note, fell back to the chip.
    static func of(text: String, caretLocation: Int) -> GhostTextEligibility {
        let nsText = text as NSString
        let atEndOfLine: Bool
        if caretLocation >= nsText.length {
            atEndOfLine = true
        } else {
            let next = nsText.character(at: caretLocation)
            atEndOfLine = next == 0x0A || next == 0x0D || next == 0x2028 || next == 0x2029
        }
        return GhostTextEligibility(
            caretAtEndOfLine: atEndOfLine,
            isRightToLeft: GhostTextGeometry.isRightToLeft(text)
        )
    }

    // A line-level caret rect is already the end of its line — that is all this
    // check was ever standing in for — so it qualifies on its own. The direction
    // check never yields, because drawing on the wrong side of an RTL line is
    // wrong however the geometry was found.
    func allows(_ caret: CaretGeometry) -> Bool {
        !isRightToLeft && (caretAtEndOfLine || !caret.isPrecise)
    }
}

// The arithmetic behind ghost text, kept free of AppKit so it can be tested
// without a screen, a window, or a live text field.
enum GhostTextGeometry {
    static let defaultFontSize: CGFloat = 13

    // The caret rect's height is the field's *line* height, not its point size:
    // the system font at 13 pt occupies roughly a 16 pt line box. Undo that
    // ratio to land near the size the app is actually drawing.
    static func fontSize(forCaretHeight height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 6, height < 200 else { return defaultFontSize }
        return min(48, max(9, (height / 1.25).rounded()))
    }

    // The field's own reported size wins whenever there is one. The ratio above
    // is only an inference from the line box and rounds to a whole point, so it
    // misses by one or two — invisible for a floating panel, obvious for text
    // pretending to already be in the sentence.
    static func fontSize(forCaretHeight height: CGFloat, reportedSize: CGFloat?) -> CGFloat {
        guard let reportedSize, reportedSize.isFinite, reportedSize >= 6, reportedSize <= 200
        else { return fontSize(forCaretHeight: height) }
        return reportedSize
    }

    // Ghost text has to sit on the same baseline as the line it continues, and
    // AX gives us the line box rather than the baseline. A fifth of the line
    // height is a stand-in for the descender space below it, used only when the
    // font is unknown — it is visibly a guess when ghost text abuts real words.
    static func baselineY(forCaretRect rect: CGRect) -> CGFloat {
        rect.maxY - rect.height * 0.2
    }

    // With the font known, the baseline is arithmetic rather than estimate: it
    // sits `baselineOffset` below the top of the text's own line box, and any
    // height the field's line box has beyond that is padding split evenly above
    // and below.
    static func baselineY(
        forCaretRect rect: CGRect,
        lineHeight: CGFloat?,
        baselineOffset: CGFloat?
    ) -> CGFloat {
        guard
            let lineHeight, let baselineOffset,
            lineHeight > 0, baselineOffset > 0,
            lineHeight <= rect.height + 4
        else { return baselineY(forCaretRect: rect) }

        let halfLeading = max(0, (rect.height - lineHeight) / 2)
        return rect.minY + halfLeading + baselineOffset
    }

    static let trailingGap: CGFloat = 6

    // Zero on purpose. The word boundary is already carried by the suggestion
    // text itself — a leading space when the writer finished a word, nothing at
    // all mid-word — so any gap added here is a second space the sentence never
    // asked for.
    static let caretGap: CGFloat = 0
    private static let minimumWidth: CGFloat = 60

    // How much room is left between the caret and the right edge of the field
    // it is in. Ghost text is truncated to fit rather than moved, because
    // moving it away from the caret is what breaks the illusion.
    //
    // The floor means a very narrow field gets a little overhang instead of a
    // suggestion too clipped to read.
    static func widthBudget(
        caretMaxX: CGFloat,
        fieldMaxX: CGFloat?,
        screenMaxX: CGFloat
    ) -> CGFloat {
        let rightEdge = min(fieldMaxX ?? screenMaxX, screenMaxX)
        return max(minimumWidth, rightEdge - caretMaxX - trailingGap)
    }

    // Ghost text is drawn to the right of the caret, which is the wrong side
    // for a right-to-left line. Rather than mirror the layout — and get the
    // truncation, the hint glyph, and the mic dot wrong with it — callers fall
    // back to the chip when this returns true.
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if isStrongRightToLeft(scalar) { return true }
            if Character(scalar).isLetter { return false }
        }
        return false
    }

    private static func isStrongRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Arabic-Indic digits sit inside the Arabic block but carry no
        // direction of their own, so a phone number is not an RTL line.
        case 0x0660...0x0669, 0x06F0...0x06F9:
            return false
        case 0x0590...0x08FF,      // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan
             0xFB1D...0xFDFF,      // Hebrew and Arabic presentation forms
             0xFE70...0xFEFF,      // Arabic presentation forms-B
             0x10800...0x10FFF,    // Cypriot, Phoenician, Kharoshthi, Avestan…
             0x1E800...0x1EFFF:    // Mende Kikakui, Adlam, Arabic Mathematical
            return true
        default:
            return false
        }
    }
}
