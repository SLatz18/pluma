import AVFoundation
import Foundation

/// Groups installed `AVSpeechSynthesisVoice`s so the Reader picker can surface
/// Premium and Enhanced voices ahead of compact defaults.
enum ReaderVoiceCatalog {
    enum Tier: Int, Comparable, CaseIterable, Sendable {
        case premium = 3
        case enhanced = 2
        case standard = 1

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var title: String {
            switch self {
            case .premium: "Premium"
            case .enhanced: "Enhanced"
            case .standard: "Standard"
            }
        }

        init(quality: AVSpeechSynthesisVoiceQuality) {
            switch quality {
            case .premium: self = .premium
            case .enhanced: self = .enhanced
            default: self = .standard
            }
        }
    }

    struct Section: Sendable {
        let tier: Tier
        let voices: [AVSpeechSynthesisVoice]

        var title: String { tier.title }
    }

    struct Entry: Sendable {
        let voice: AVSpeechSynthesisVoice
        let tier: Tier

        var pickerLabel: String {
            "\(voice.name) (\(tier.title))"
        }
    }

    static func tier(for voice: AVSpeechSynthesisVoice) -> Tier {
        Tier(quality: voice.quality)
    }

    static func entries(
        from voices: [AVSpeechSynthesisVoice],
        languageCode: String
    ) -> [Entry] {
        let matches = voices.filter { $0.language.hasPrefix(languageCode) }
        let scoped = matches.isEmpty ? voices : matches
        return scoped
            .map { Entry(voice: $0, tier: tier(for: $0)) }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
                return lhs.voice.name.localizedCaseInsensitiveCompare(rhs.voice.name)
                    == .orderedAscending
            }
    }

    static func sections(from entries: [Entry]) -> [Section] {
        Tier.allCases
            .sorted(by: >)
            .compactMap { tier in
                let voices = entries.filter { $0.tier == tier }.map(\.voice)
                guard !voices.isEmpty else { return nil }
                return Section(tier: tier, voices: voices)
            }
    }

    static func hasPremium(in entries: [Entry]) -> Bool {
        entries.contains { $0.tier == .premium }
    }

    /// Prefer an installed Premium voice for the language; otherwise Enhanced;
    /// otherwise empty (system default).
    static func preferredIdentifier(in entries: [Entry]) -> String {
        if let premium = entries.first(where: { $0.tier == .premium }) {
            return premium.voice.identifier
        }
        if let enhanced = entries.first(where: { $0.tier == .enhanced }) {
            return enhanced.voice.identifier
        }
        return ""
    }

    /// Maps Reader's AVSpeech rate slider onto OpenAI's `speed` (0.25…4.0).
    /// Default Reader rate maps to 1.0; ends stay in a natural listening band.
    static func openAISpeed(fromReaderRate rate: Double) -> Double {
        let lower = Preferences.readerRateRange.lowerBound
        let upper = Preferences.readerRateRange.upperBound
        let mid = Preferences.defaultReaderRate
        let clamped = min(max(rate, lower), upper)
        let span = upper - lower
        guard span > 0 else { return 1.0 }
        return 1.0 + ((clamped - mid) / span) * 0.6
    }
}
