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

// MARK: - Where status lives

/// Where the app's own remarks — progress, permission nags, failures — are
/// shown. Text the writer is about to accept (ghost text, the suggestion chip,
/// the live transcript) always sits at the caret; only status moves.
enum StatusPlacement: String, CaseIterable, Sendable {
    /// A glass capsule that descends out from under the notch. Displays without
    /// a notch get the same capsule hanging from the top centre of the screen.
    case notch
    /// The chip near the caret (or the pointer when there is no field), as
    /// before.
    case caret

    static let defaultPlacement: StatusPlacement = .notch

    var title: String {
        switch self {
        case .notch: "At the notch"
        case .caret: "Near the caret"
        }
    }
}

/// Decides, for one presentation, whether it belongs at the notch. Pure so the
/// arbitration can be tested without a screen or a panel.
enum OverlayPlacementPolicy {
    static func usesNotch(
        for content: OverlayPresentation.Content,
        placement: StatusPlacement,
        companionRunning: Bool
    ) -> Bool {
        guard case .status = content else { return false }
        return placement == .notch && !companionRunning
    }
}

/// Geometry for the notch HUD. All rects are Cocoa (bottom-left origin) in the
/// global screen space `NSScreen.frame` uses. Pure so it can be tested against
/// hand-built displays.
enum NotchGeometry {
    /// What the HUD needs to know about the display it will hang from.
    struct Display: Equatable, Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
        /// The hardware notch, or nil on displays without one.
        let notch: CGRect?
    }

    /// The notch is the gap between the two menu-bar areas along the top edge.
    /// A screen that reports a top safe area but no auxiliary areas gets a
    /// centred notch of an assumed width rather than none: the safe area is the
    /// stronger signal.
    static func notchRect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGRect? {
        guard safeAreaTop > 0 else { return nil }
        let top = screenFrame.maxY - safeAreaTop
        if let left = auxiliaryTopLeft, let right = auxiliaryTopRight, right.minX > left.maxX {
            return CGRect(x: left.maxX, y: top, width: right.minX - left.maxX, height: safeAreaTop)
        }
        let width = min(DS.Overlay.assumedNotchWidth, screenFrame.width)
        return CGRect(x: screenFrame.midX - width / 2, y: top, width: width, height: safeAreaTop)
    }

    /// The narrowest the glass may be on a notched display: the notch itself
    /// plus a flare on each side, so the corners begin past the notch's edges.
    static func minimumWidth(for display: Display) -> CGFloat {
        guard let notch = display.notch else { return 0 }
        return notch.width + 2 * DS.Overlay.notchFlare
    }

    /// How much of the HUD's height sits above the message: the headroom
    /// hidden offscreen plus the notch it hangs under. Displays without a notch
    /// have neither, so the capsule starts at its own top edge.
    static func hiddenTopHeight(for display: Display) -> CGFloat {
        guard let notch = display.notch else { return 0 }
        return DS.Overlay.notchHeadroom + notch.height
    }

    /// The panel frame for a HUD whose fitting size is `size` (already
    /// including `hiddenTopHeight`). With a notch the frame is centred on it and
    /// tops out `notchHeadroom` above the screen; without one it hangs just
    /// under the menu bar at the screen's centre. Either way it stays inside
    /// the display horizontally.
    static func panelFrame(for display: Display, size: CGSize) -> CGRect {
        let width = min(size.width, display.frame.width)
        let centerX: CGFloat
        let top: CGFloat
        if let notch = display.notch {
            centerX = notch.midX
            top = display.frame.maxY + DS.Overlay.notchHeadroom
        } else {
            centerX = display.visibleFrame.midX
            top = display.visibleFrame.maxY - DS.Overlay.screenInset
        }
        let minX = max(display.frame.minX, min(centerX - width / 2, display.frame.maxX - width))
        return CGRect(x: minX, y: top - size.height, width: width, height: size.height)
    }

    /// The frame the HUD starts from when it appears: the same shape pushed up
    /// by its visible height, so it is tucked behind the notch and menu bar and
    /// descends into view.
    static func tuckedFrame(for display: Display, target: CGRect) -> CGRect {
        let visibleHeight = target.height - hiddenTopHeight(for: display)
        return target.offsetBy(dx: 0, dy: max(0, visibleHeight))
    }
}

@MainActor
extension NotchGeometry {
    static func display(for screen: NSScreen) -> Display {
        Display(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notch: notchRect(
                screenFrame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea
            )
        )
    }

    /// The display a status should hang from: the one holding the caret (or
    /// pointer) the caller anchored at, then the one under the mouse, then the
    /// first. `anchor` is AX top-left-origin relative to the primary display.
    static func screen(forTopLeftAnchor anchor: CGPoint?) -> NSScreen? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        if let anchor {
            let point = CGPoint(x: anchor.x, y: primary.frame.height - anchor.y)
            if let hit = screens.first(where: { NSPointInRect(point, $0.frame) }) {
                return hit
            }
        }
        let mouse = NSEvent.mouseLocation
        return screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? primary
    }
}

/// Other apps that draw their own UI around the notch. Two capsules fighting
/// over the same pixels helps nobody, so the HUD yields to them and falls back
/// to the caret — the same courtesy the Caps expander extends to Hyperkey.
@MainActor
enum NotchCompanions {
    static let bundleIdentifiers: Set<String> = [
        "com.henrikruscon.Alcove",
        "theboringteam.boringnotch",
        "com.lo.NotchNook",
        "com.bezlab.NotchNook",
        "com.ebbinghaus.notchdrop",
    ]

    static let localizedNames: Set<String> = [
        "Alcove", "boring.notch", "NotchNook", "NotchDrop", "Dynamic Notch",
    ]

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if let bundleID = app.bundleIdentifier, bundleIdentifiers.contains(bundleID) {
                return true
            }
            if let name = app.localizedName, localizedNames.contains(name) {
                return true
            }
            return false
        }
    }
}
