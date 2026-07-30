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
        static let capsule: CGFloat = 999
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
    }

    enum Overlay {
        static let textSize: CGFloat = 13
        static let horizontalInset: CGFloat = 11
        static let verticalInset: CGFloat = 5
        static let itemSpacing: CGFloat = 8
        static let maximumTextWidth: CGFloat = 460
        static let screenInset: CGFloat = 6
    }

    enum FeatureColor: String, Hashable, Sendable {
        case rewrite
        case autocomplete
        case dictation
        case shortcut

        var color: Color {
            switch self {
            case .rewrite: .accentColor
            case .autocomplete: .indigo
            case .dictation: .pink
            case .shortcut: .mint
            }
        }

        var nsColor: NSColor {
            switch self {
            case .rewrite: .controlAccentColor
            case .autocomplete: .systemIndigo
            case .dictation: .systemPink
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
    static let strongHairline = Color.primary.opacity(0.14)

    static let pageTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let cardTitle = Font.headline
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
        case autocomplete, dictation, shortcut

        var color: Color {
            switch self {
            case .improve: .blue
            case .shorten: .purple
            case .grammar: .green
            case .professional: .orange
            case .autocomplete: FeatureColor.autocomplete.color
            case .dictation: FeatureColor.dictation.color
            case .shortcut: FeatureColor.shortcut.color
            }
        }
    }
}

typealias DS = PlumaTheme
