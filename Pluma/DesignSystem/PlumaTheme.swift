import AppKit
import SwiftUI

enum PlumaTheme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 22
        static let page: CGFloat = 28
    }

    enum Radius {
        static let badge: CGFloat = 6
        static let inset: CGFloat = 10
        static let tile: CGFloat = 11
        static let card: CGFloat = 14
    }

    enum Control {
        static let iconTile: CGFloat = 42
        static let shortcutHeight: CGFloat = 24
        static let providerWidth: CGFloat = 180
        static let pageMaxWidth: CGFloat = 820
    }

    enum Motion {
        static let present: TimeInterval = 0.16
        static let dismiss: TimeInterval = 0.12
        static let flash: Duration = .seconds(2.5)
        static let rise: CGFloat = 5
        /// The one spring for revealing/hiding rows and disclosures, so every
        /// surface settles with the same character.
        static let spring = Animation.spring(response: 0.32, dampingFraction: 0.85)

        /// Whether the user has asked macOS to reduce motion. Non-SwiftUI
        /// surfaces (AppKit panels, overlay controllers) should consult this;
        /// SwiftUI views should prefer `@Environment(\.accessibilityReduceMotion)`
        /// so they re-render when the setting changes.
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// The shared reveal spring, or `nil` (instant transitions) when the
        /// user has Reduce Motion enabled. Pass the view's
        /// `@Environment(\.accessibilityReduceMotion)` value.
        static func reveal(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : spring
        }
    }

    enum Overlay {
        static let textSize: CGFloat = 13
        /// The pill's corner radius is the card radius, so the chip at the
        /// caret and the cards in the main window share one curvature. At the
        /// standard pill height this resolves to a capsule.
        static let radius: CGFloat = Radius.card
        static let height: CGFloat = 28
        static let horizontalInset: CGFloat = 11
        static let verticalInset: CGFloat = 5
        static let itemSpacing: CGFloat = 8
        static let maximumTextWidth: CGFloat = 460
        static let screenInset: CGFloat = 6
        static let verticalJitterTolerance: CGFloat = 8
    }

    enum FeatureColor: String, Hashable, Sendable {
        case rewrite
        case autocomplete
        case dictation
        case reader
        case shortcut

        var color: Color {
            switch self {
            case .rewrite: .accentColor
            case .autocomplete: .indigo
            case .dictation: .pink
            case .reader: .teal
            case .shortcut: .mint
            }
        }

        /// The same tints for AppKit surfaces (the overlay pill and ghost
        /// text), so a feature wears one colour everywhere.
        var nsColor: NSColor {
            switch self {
            case .rewrite: .controlAccentColor
            case .autocomplete: .systemIndigo
            case .dictation: .systemPink
            case .reader: .systemTeal
            case .shortcut: .systemMint
            }
        }
    }

    enum Tone: String, CaseIterable, Sendable {
        case neutral
        case success
        case attention
        case recording
        case failure

        var color: Color {
            switch self {
            case .neutral: .secondary
            case .success: .green
            case .attention: .orange
            case .recording, .failure: .red
            }
        }

        /// The AppKit mirror of the same palette, for the overlay pill.
        var nsColor: NSColor {
            switch self {
            case .neutral: .secondaryLabelColor
            case .success: .systemGreen
            case .attention: .systemOrange
            case .recording, .failure: .systemRed
            }
        }
    }

    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let insetBackground = Color(nsColor: .textBackgroundColor)
    static let hairline = Color.primary.opacity(0.07)

    /// Rounded system font for AppKit text that should speak the same
    /// typographic dialect as the SwiftUI `design: .rounded` titles. Falls
    /// back to the plain system font if the rounded design is unavailable.
    static func roundedUIFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return rounded
    }

    static let pageTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let cardBody = Font.subheadline
    static let meta = Font.caption
    static let eyebrow = Font.caption2.weight(.bold)

    static let cardRadius = Radius.card
    static let tileRadius = Radius.tile
    static let insetRadius = Radius.inset
    static let cardPadding = Spacing.large
    static let pagePadding = Spacing.page
    static let sectionGap = Spacing.xLarge

    enum Feature {
        case improve, shorten, grammar, professional
        case autocomplete, dictation, reader, shortcut

        var color: Color {
            switch self {
            case .improve: .blue
            case .shorten: .purple
            case .grammar: .green
            case .professional: .orange
            case .autocomplete: FeatureColor.autocomplete.color
            case .dictation: FeatureColor.dictation.color
            case .reader: FeatureColor.reader.color
            case .shortcut: FeatureColor.shortcut.color
            }
        }
    }
}

typealias DS = PlumaTheme
