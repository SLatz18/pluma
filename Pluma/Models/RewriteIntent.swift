import Foundation

enum RewriteIntent: String, CaseIterable, Codable, Identifiable, Sendable {
    case improve
    case shorten
    case grammar
    case professional

    var id: String { rawValue }

    var promptID: String { "rewrite.\(rawValue)" }

    var title: String {
        switch self {
        case .improve: "Improve"
        case .shorten: "Shorten"
        case .grammar: "Fix Grammar"
        case .professional: "Professional"
        }
    }

    var shortDescription: String {
        switch self {
        case .improve: "Clearer and more natural"
        case .shorten: "Keep the meaning, lose the extra"
        case .grammar: "Correct spelling and grammar"
        case .professional: "Polished and confident"
        }
    }

    var symbolName: String {
        switch self {
        case .improve: "wand.and.sparkles"
        case .shorten: "text.badge.minus"
        case .grammar: "checkmark.seal"
        case .professional: "briefcase"
        }
    }

    /// Live editing goal. Honors a Developer-page override when one is set.
    var directive: String {
        PromptOverrides.text(for: promptID, default: shippedDirective)
    }

    /// Shipped copy — the Reset target and the default for an untouched install.
    var shippedDirective: String {
        switch self {
        case .improve:
            "Improve clarity, flow, and word choice while preserving the writer's voice and register. "
                + "Never make the text more formal than the source: casual phrasing stays casual "
                + "(\"fix them up\", not \"revise them\"; \"you've seen\", not \"you have seen\")."
        case .shorten:
            "Make the text meaningfully shorter while preserving every important point."
        case .grammar:
            "Correct grammar, spelling, punctuation, and awkward phrasing without changing tone. "
                + "Expand texting shorthand to the words the writer meant in context "
                + "(\"u c the deck\" → \"you have seen the deck\", never \"you can see the deck\"), "
                + "and do not add modals the writer did not write. "
                + "Translate register markers instead of deleting them: a greeting stays a greeting "
                + "(\"yo\" → \"hey\"), and candor or emphasis stays (\"ngl\" → \"honestly\")."
        case .professional:
            "Make the text polished, concise, professional, and confident without sounding stiff."
        }
    }

    static let defaultIntent: RewriteIntent = .improve
}
