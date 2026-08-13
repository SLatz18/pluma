import Foundation

/// A directive card for the dictation-cleanup builder: each case is one
/// instruction the speaker can stack, in order, to shape the AI cleanup pass.
/// Mirrors `RewriteIntent`, but these compose into a single cleanup prompt.
enum CleanupDirective: String, CaseIterable, Codable, Identifiable, Sendable {
    case removeFiller
    case fixGrammar
    case addPunctuation
    case bulletPoints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .removeFiller: "Remove Filler"
        case .fixGrammar: "Fix Grammar"
        case .addPunctuation: "Add Punctuation"
        case .bulletPoints: "Bullet Points"
        }
    }

    var shortDescription: String {
        switch self {
        case .removeFiller: "Drop ums, false starts, repeats"
        case .fixGrammar: "Correct slips without rephrasing"
        case .addPunctuation: "Periods, commas, capitals"
        case .bulletPoints: "One bullet per idea"
        }
    }

    var symbolName: String {
        switch self {
        case .removeFiller: "waveform.badge.minus"
        case .fixGrammar: "checkmark.seal"
        case .addPunctuation: "textformat"
        case .bulletPoints: "list.bullet"
        }
    }

    /// The cleanup step added to the dictation prompt when this card is in
    /// the chain.
    var promptDirective: String {
        switch self {
        case .removeFiller:
            "Remove filler words, false starts, stutters, and accidental "
                + "repetitions."
        case .fixGrammar:
            "Correct grammatical slips the speaker made — agreement, tense, "
                + "and dropped words — without rephrasing or changing their wording."
        case .addPunctuation:
            "Add correct punctuation and capitalization, but if the text is a "
                + "fragment rather than a sentence, leave it without closing "
                + "punctuation. Convert spoken punctuation instructions such as "
                + "\"period\" or \"new line\" into the punctuation itself."
        case .bulletPoints:
            "Format the result as a bulleted list, one bullet per distinct "
                + "point the speaker made, each starting with \"- \"."
        }
    }

    /// Matching today's shipped behavior: the legacy cleanup directive removes
    /// filler and fixes punctuation. When the chain equals this default, the
    /// composer emits exactly the legacy prompt.
    static let defaultChain: [CleanupDirective] = [.removeFiller, .addPunctuation]
}
