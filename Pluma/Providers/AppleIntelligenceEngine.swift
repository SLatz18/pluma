import Foundation
import FoundationModels

enum AppleIntelligenceEngine {
    private static let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    // Foundation Models cancels overlapping sessions on the same system model.
    // Every rewrite, completion, and spelling pass shares this gate so only one
    // LanguageModelSession is live at a time — others wait their turn.
    private static let gate = SessionGate()

    private actor SessionGate {
        func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
            try await operation()
        }
    }

    static func status() -> ProviderStatus {
        switch model.availability {
        case .available:
            ProviderStatus(
                state: .ready,
                title: "Apple Intelligence ready",
                detail: "Private and on-device.",
                symbolName: "apple.intelligence"
            )
        case .unavailable(.modelNotReady):
            ProviderStatus(
                state: .waiting,
                title: "Model downloading",
                detail: "Apple Intelligence will be ready when the download finishes.",
                symbolName: "arrow.down.circle"
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            ProviderStatus(
                state: .unavailable,
                title: "Apple Intelligence is off",
                detail: "Turn it on in System Settings to use the default model.",
                symbolName: "apple.intelligence"
            )
        case .unavailable(.deviceNotEligible):
            ProviderStatus(
                state: .unavailable,
                title: "Mac not supported",
                detail: "Choose Ollama to use another local model.",
                symbolName: "exclamationmark.triangle"
            )
        @unknown default:
            ProviderStatus(
                state: .unavailable,
                title: "Model unavailable",
                detail: "Apple Intelligence is not available right now.",
                symbolName: "exclamationmark.triangle"
            )
        }
    }

    static func rewrite(_ text: String, directive: String) async throws -> String {
        try await gate.run {
            try await rewriteUnlocked(text, directive: directive)
        }
    }

    static func complete(
        _ context: String,
        surrounding: String? = nil,
        memory: String? = nil,
        styleProfile: String? = nil,
        directives: [CompletionDirective] = CompletionDirective.defaultChain
    ) async throws -> String {
        try await gate.run {
            try await completeUnlocked(
                context, surrounding: surrounding, memory: memory, styleProfile: styleProfile,
                directives: directives
            )
        }
    }

    // One corrected word for a misspelling or garbled fragment. Queued behind
    // the same gate as completions so a spelling pass never races a suggestion.
    // `preceding` is the text before the token; the model uses it to pick among
    // plausible fixes (system admini → administrator).
    static func correctSpelling(word: String, preceding: String) async throws -> String {
        try await gate.run {
            try await correctSpellingUnlocked(word: word, preceding: preceding)
        }
    }

    private static func rewriteUnlocked(_ text: String, directive: String) async throws -> String {
        guard model.isAvailable else {
            throw RewriteEngineError.modelUnavailable(status().detail)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: PromptComposer.systemInstructions
        )
        let response = try await session.respond(
            to: PromptComposer.userPrompt(directive: directive, text: text)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func completeUnlocked(
        _ context: String,
        surrounding: String?,
        memory: String?,
        styleProfile: String?,
        directives: [CompletionDirective]
    ) async throws -> String {
        guard model.isAvailable else {
            throw RewriteEngineError.modelUnavailable(status().detail)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: PromptComposer.completionInstructions(
                styleProfile: styleProfile, directives: directives
            )
        )
        let response = try await session.respond(
            to: PromptComposer.completionUserPrompt(
                context: context, surrounding: surrounding, memory: memory
            ),
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 80)
        )
        let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw RewriteEngineError.invalidResponse
        }
        return output
    }

    private static func correctSpellingUnlocked(word: String, preceding: String) async throws -> String {
        guard model.isAvailable else {
            throw RewriteEngineError.modelUnavailable(status().detail)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: PromptComposer.spellingCorrectionInstructions
        )
        let options = GenerationOptions(temperature: 0.0, maximumResponseTokens: 8)
        let response = try await session.respond(
            to: PromptComposer.spellingCorrectionUserPrompt(word: word, preceding: preceding),
            options: options
        )
        let first = SpellCorrection.sanitizedModelReplacement(
            response.content, forMisspelling: word, preceding: preceding
        )
        if !first.isEmpty { return first }

        // First pass often returns a noun ("separation") where grammar wants
        // a verb ("separate"). One retry in the same session with an explicit
        // verb constraint recovers that without opening another gated session.
        guard SpellCorrection.precedingLikelyNeedsVerb(preceding) else {
            throw RewriteEngineError.invalidResponse
        }
        let rejected = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let retry = try await session.respond(
            to: PromptComposer.spellingCorrectionVerbRetryPrompt(
                word: word, preceding: preceding, rejected: rejected
            ),
            options: options
        )
        let second = SpellCorrection.sanitizedModelReplacement(
            retry.content, forMisspelling: word, preceding: preceding
        )
        guard !second.isEmpty else {
            throw RewriteEngineError.invalidResponse
        }
        return second
    }
}
