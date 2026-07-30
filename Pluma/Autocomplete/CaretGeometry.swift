import AppKit
import ApplicationServices
import Foundation

// Which probe produced a caret rect. Worth naming rather than reducing to a
// bool: the developer-mode inspector reports it, and so does verbose logging,
// because "which probe won" is the first question when ghost text lands wrong.
enum CaretSource: String, Equatable {
    case exactCaret
    case characterBefore
    case lineBounds

    var title: String {
        switch self {
        case .exactCaret: "exact caret"
        case .characterBefore: "character before caret"
        case .lineBounds: "line bounds"
        }
    }
}

// The typeface the field is drawing, when Accessibility will name it. Ghost text
// that sits directly against the writer's own words has to match it: deriving a
// size from the caret's height lands a point or two off and always in the system
// font, which reads as a different kind of text rather than a continuation.
struct FieldFont: Equatable, Sendable {
    let name: String
    let size: CGFloat
}

// Where the text cursor is, how tall the line it sits on is, and — when the app
// will say — what font that line is set in. The height is the fallback clue:
// it is the field's line height, which is all Accessibility offers when the
// attributed text is unavailable.
//
// Coordinates are AX's: top-left origin, relative to the primary display.
struct CaretGeometry: Equatable {
    let rect: CGRect
    let source: CaretSource
    let font: FieldFont?

    init(rect: CGRect, source: CaretSource, font: FieldFont? = nil) {
        self.rect = rect
        self.source = source
        self.font = font
    }

    // The line-level fallback gets the line right but guesses the column.
    var isPrecise: Bool { source != .lineBounds }
}

// The three Accessibility reads the probes need. A protocol so the ordering
// logic below can be tested with canned geometry instead of a live app.
protocol CaretProbing {
    func boundsForRange(_ range: CFRange) -> CGRect?
    func insertionPointLineNumber() -> Int?
    func rangeForLine(_ line: Int) -> CFRange?
    var elementFrame: CGRect? { get }
    func fieldFont(at location: Int) -> FieldFont?
}

// Most fields cannot answer this — Chromium and Electron in particular — and
// ghost text falls back to the caret-height estimate when they don't, so the
// requirement carries a default rather than forcing every probe to refuse it.
extension CaretProbing {
    func fieldFont(at location: Int) -> FieldFont? { nil }
}

enum CaretResolver {
    // Tried in order, first plausible answer wins. Each step exists because
    // some real app fails the one before it.
    static func resolve(location: Int, using probe: some CaretProbing) -> CaretGeometry? {
        let field = probe.elementFrame
        let font = probe.fieldFont(at: location)

        // 1. The caret itself: a zero-length range at the insertion point.
        //    Native AppKit and WebKit fields answer this correctly.
        if
            let rect = probe.boundsForRange(CFRange(location: location, length: 0)),
            isPlausible(rect, in: field)
        {
            return CaretGeometry(rect: rect, source: .exactCaret, font: font)
        }

        // 2. The character before the caret. Chromium and Electron hand back a
        //    degenerate rect at the screen's bottom-left for a zero-length
        //    range at end-of-text, but report the preceding character fine —
        //    and the caret sits at its trailing edge.
        if
            location > 0,
            let rect = probe.boundsForRange(CFRange(location: location - 1, length: 1)),
            isPlausible(rect, in: field)
        {
            return CaretGeometry(
                rect: CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height),
                source: .characterBefore,
                font: font
            )
        }

        // 3. The whole line the caret is on. Loses the column, but a caret at
        //    the end of the line — the only case ghost text is drawn in — is
        //    exactly the line's trailing edge.
        if
            let line = probe.insertionPointLineNumber(),
            let lineRange = probe.rangeForLine(line),
            let rect = probe.boundsForRange(lineRange),
            isPlausible(rect, in: field)
        {
            return CaretGeometry(
                rect: CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height),
                source: .lineBounds,
                font: font
            )
        }

        return nil
    }

    // A rect is believed only if it has real height and starts inside the field
    // that produced it. Without this check, Chromium's bottom-left garbage rect
    // would sail through as a perfectly valid caret.
    static func isPlausible(_ rect: CGRect, in fieldFrame: CGRect?) -> Bool {
        guard rect.height > 0, rect.height < 400, rect.width < 10_000 else { return false }
        guard rect.origin.x.isFinite, rect.origin.y.isFinite else { return false }
        guard let fieldFrame else { return true }
        return fieldFrame.insetBy(dx: -8, dy: -8).contains(rect.origin)
    }
}

// The live implementation. Every read is a synchronous AX round trip, so
// callers should resolve once per update rather than per draw.
struct AXCaretProbe: CaretProbing {
    let element: AXUIElement

    // Spelled out rather than taken from kAXFontTextAttribute and friends: those
    // are declared as mutable `Unmanaged<CFString>` globals, which Swift 6 will
    // not let a nonisolated context touch. The names themselves are stable API.
    private static let axFontAttribute = NSAttributedString.Key("AXFont")
    private static let axFontName = "AXFontName"
    private static let axFontSize = "AXFontSize"

    var elementFrame: CGRect? { FocusedFieldTracker.frame(of: element) }

    func boundsForRange(_ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    func insertionPointLineNumber() -> Int? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXInsertionPointLineNumberAttribute as CFString, &value
            ) == .success
        else { return nil }
        return value as? Int
    }

    // The attributed text around the caret carries the font the field is really
    // drawing. Read the character *before* the caret, because at the end of the
    // text there is nothing at the caret itself to carry attributes.
    func fieldFont(at location: Int) -> FieldFont? {
        var range = CFRange(location: max(0, location - 1), length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXAttributedStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &value
            ) == .success,
            let attributed = value as? NSAttributedString,
            attributed.length > 0
        else { return nil }

        let attributes = attributed.attributes(at: 0, effectiveRange: nil)

        // AppKit text views hand back a real NSFont. Everything else that
        // answers at all uses the Accessibility text attribute, whose value is a
        // dictionary of name and size rather than a font object.
        if let font = attributes[.font] as? NSFont {
            return FieldFont(name: font.fontName, size: font.pointSize)
        }
        if
            let descriptor = attributes[Self.axFontAttribute] as? [String: Any],
            let name = descriptor[Self.axFontName] as? String,
            let size = descriptor[Self.axFontSize] as? NSNumber
        {
            return FieldFont(name: name, size: CGFloat(size.doubleValue))
        }

        DebugLog.log(
            "no font in AX text attributes: \(attributes.keys.map(\.rawValue).sorted())",
            at: .verbose
        )
        return nil
    }

    func rangeForLine(_ line: Int) -> CFRange? {
        let lineValue = NSNumber(value: line) as CFNumber

        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXRangeForLineParameterizedAttribute as CFString,
                lineValue,
                &rangeValue
            ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
