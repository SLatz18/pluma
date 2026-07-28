import Foundation

enum RewriteRunner {
    static func rewrite(
        provider: RewriteProviderChoice,
        intent: RewriteIntent,
        text: String,
        ollamaModel: String
    ) async throws -> String {
        try await rewrite(
            provider: provider,
            directive: intent.directive,
            text: text,
            ollamaModel: ollamaModel
        )
    }

    static func rewrite(
        provider: RewriteProviderChoice,
        directive: String,
        text: String,
        ollamaModel: String
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.rewrite(text, directive: directive)
        case .ollama:
            try await OllamaEngine().rewrite(text, directive: directive, model: ollamaModel)
        }
    }

    // Tidies a raw dictation transcript. Returns nil rather than throwing so a
    // caller can fall back to the raw transcript: losing the user's words to a
    // model failure is never acceptable.
    static func cleanUpDictation(
        provider: RewriteProviderChoice,
        transcript: String,
        ollamaModel: String
    ) async -> String? {
        guard DictationTranscript.isWorthCleaningUp(transcript) else { return nil }
        do {
            let output = try await rewrite(
                provider: provider,
                directive: PromptComposer.dictationDirective,
                text: transcript,
                ollamaModel: ollamaModel
            )
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return cleaned
        } catch {
            DebugLog.log("dictation cleanup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func complete(
        provider: RewriteProviderChoice,
        context: String,
        surrounding: String? = nil,
        ollamaModel: String
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.complete(context, surrounding: surrounding)
        case .ollama:
            try await OllamaEngine().complete(context, model: ollamaModel, surrounding: surrounding)
        }
    }
}
