import Foundation

/// A directive card for the autocomplete builder: each case is one instruction
/// the writer can stack, in order, to shape how completions behave. Mirrors
/// `RewriteIntent`, but these compose into a single prompt rather than running
/// as separate steps.
enum CompletionDirective: String, CaseIterable, Codable, Identifiable, Sendable {
    case matchTone
    case shortCompletions
    case avoidCliches
    case fullSentences

    var id: String { rawValue }

    var promptID: String { "autocomplete.\(rawValue)" }

    var title: String {
        switch self {
        case .matchTone: "Match My Tone"
        case .shortCompletions: "Keep It Short"
        case .avoidCliches: "Avoid Clichés"
        case .fullSentences: "Full Sentences"
        }
    }

    var shortDescription: String {
        switch self {
        case .matchTone: "Sound like me, not the model"
        case .shortCompletions: "A word or phrase, never a clause"
        case .avoidCliches: "Plain, specific wording"
        case .fullSentences: "Finish the thought completely"
        }
    }

    var symbolName: String {
        switch self {
        case .matchTone: "person.wave.2"
        case .shortCompletions: "text.badge.minus"
        case .avoidCliches: "sparkles.slash"
        case .fullSentences: "text.append"
        }
    }

    /// The sentence added to the completion system prompt when this card is in
    /// the chain. Honors a Developer-page override when one is set.
    var promptDirective: String {
        PromptOverrides.text(for: promptID, default: shippedPromptDirective)
    }

    /// Shipped copy — the Reset target and the default for an untouched install.
    var shippedPromptDirective: String {
        switch self {
        case .matchTone:
            "Match the writer's tone, register, and vocabulary exactly: "
                + "casual stays casual, formal stays formal, and slang or "
                + "shorthand the writer uses is fair game."
        case .shortCompletions:
            "Prefer the shortest useful continuation — a word or short phrase "
                + "over a clause — even when the direction of the sentence is clear."
        case .avoidCliches:
            "Avoid clichés, stock phrases, and buzzwords; choose plain, "
                + "specific wording instead."
        case .fullSentences:
            "When the direction of the sentence is clear, complete the full "
                + "sentence through to its natural end instead of stopping "
                + "after a word or two."
        }
    }

    var hasCustomPrompt: Bool {
        PromptOverrides.isCustom(promptID, default: shippedPromptDirective)
    }

    /// Matching today's shipped behavior: the base instructions already tell
    /// the model to continue in the writer's language and tone, so the default
    /// chain is the one card that restates it. When the chain equals this
    /// default and no card is customized, the composer emits exactly the
    /// legacy prompt.
    static let defaultChain: [CompletionDirective] = [.matchTone]
}
