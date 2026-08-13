import AppKit

enum OverlayTone: String, CaseIterable, Sendable {
    case neutral
    case accent
    case recording
    case warning
    case failure

    // Routed through the design system's tone palette so the pill reports
    // status in exactly the colours the main window uses.
    var color: NSColor {
        switch self {
        case .neutral: DS.Tone.neutral.nsColor
        case .accent: DS.FeatureColor.rewrite.nsColor
        case .recording: DS.Tone.recording.nsColor
        case .warning: DS.Tone.attention.nsColor
        case .failure: DS.Tone.failure.nsColor
        }
    }
}

struct OverlayPresentation {
    enum Content {
        case ghost(text: String, caret: CaretGeometry, style: GhostStyle, fieldFrame: CGRect?)
        case suggestion(text: String)
        case dictation(transcript: String)
        case status(systemImage: String, message: String, tone: OverlayTone, pulses: Bool)
    }

    let content: Content
    let anchor: CGPoint?

    static func ghost(
        text: String,
        caret: CaretGeometry,
        style: GhostStyle,
        fieldFrame: CGRect?
    ) -> Self {
        Self(content: .ghost(text: text, caret: caret, style: style, fieldFrame: fieldFrame), anchor: nil)
    }

    static func suggestion(text: String, anchor: CGPoint) -> Self {
        Self(content: .suggestion(text: text), anchor: anchor)
    }

    static func dictation(transcript: String, anchor: CGPoint) -> Self {
        Self(content: .dictation(transcript: transcript), anchor: anchor)
    }

    static func status(
        systemImage: String,
        message: String,
        tone: OverlayTone = .neutral,
        pulses: Bool = false,
        anchor: CGPoint
    ) -> Self {
        Self(
            content: .status(
                systemImage: systemImage,
                message: message,
                tone: tone,
                pulses: pulses
            ),
            anchor: anchor
        )
    }

    static func warning(systemImage: String, message: String, anchor: CGPoint) -> Self {
        status(systemImage: systemImage, message: message, tone: .warning, anchor: anchor)
    }

    static func failure(systemImage: String, message: String, anchor: CGPoint) -> Self {
        status(systemImage: systemImage, message: message, tone: .failure, anchor: anchor)
    }
}
