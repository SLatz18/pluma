import Foundation

/// A house-voice definition (issue #20): tone directive, terminology
/// glossary, and banned constructions. Composes with any RewriteIntent.
/// Plain JSON on disk so profiles are human-reviewable and MDM-deployable.
struct StyleProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var summary: String
    var directive: String
    var bannedPhrases: [String]
    var glossary: [GlossaryTerm]
    /// Managed (MDM-pushed) profiles are read-only in the UI.
    var isManaged: Bool = false

    struct GlossaryTerm: Codable, Equatable, Sendable, Identifiable {
        var id: String { avoid }
        /// The incorrect form to catch, e.g. "MAC".
        let avoid: String
        /// The preferred form, e.g. "Mac".
        let preferred: String
    }
}

extension StyleProfile {
    static let none = StyleProfile(
        id: "none",
        name: "No Style",
        summary: "Just the selected action",
        directive: "",
        bannedPhrases: [],
        glossary: []
    )

    static let plainBusiness = StyleProfile(
        id: "plain-business",
        name: "Plain Business",
        summary: "Direct, warm, zero filler",
        directive: """
        Write in plain business English: short sentences, active voice, no
        throat-clearing openers or apologetic filler. State the point first.
        Be warm but efficient. Never sound stiff or ceremonial.
        """,
        bannedPhrases: [
            "I hope this email finds you well",
            "please don't hesitate",
            "just checking in",
            "circle back",
            "synergy"
        ],
        glossary: []
    )

    static let executiveBrief = StyleProfile(
        id: "executive-brief",
        name: "Executive Brief",
        summary: "Bottom line up front, confident",
        directive: """
        Write for an executive reader: conclusion first, then support. One
        idea per sentence. Confident, precise, no hedging stacks ("I think
        maybe we could"). Numbers over adjectives. Never bury the ask.
        """,
        bannedPhrases: [
            "I think maybe",
            "sort of",
            "kind of",
            "to be honest",
            "at the end of the day"
        ],
        glossary: []
    )

    static let supportEmpathy = StyleProfile(
        id: "support-empathy",
        name: "Support Empathy",
        summary: "Acknowledge, own it, next step",
        directive: """
        Write like a great support reply: acknowledge the person's experience
        first in their terms, take ownership without deflecting, and end with
        one concrete next step. Warm, human, never scripted-sounding.
        """,
        bannedPhrases: [
            "we apologize for any inconvenience",
            "as per our policy",
            "rest assured",
            "your understanding is appreciated"
        ],
        glossary: []
    )

    static let builtIns: [StyleProfile] = [
        .none, .plainBusiness, .executiveBrief, .supportEmpathy
    ]
}
