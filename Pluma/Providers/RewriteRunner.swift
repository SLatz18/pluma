import Foundation

enum ChainProgress {
    case starting(step: Int, of: Int, intent: RewriteIntent)
    case stepFinished(step: Int, of: Int, output: String)
}

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

    // Progress-free chain for callers that can't touch the main actor — the
    // macOS Services handler blocks its thread on a semaphore while it waits.
    static func rewriteChain(
        provider: RewriteProviderChoice,
        steps: [RewriteIntent],
        text: String,
        ollamaModel: String
    ) async throws -> String {
        guard !steps.isEmpty else { throw RewriteEngineError.emptyChain }
        var output = text
        for intent in steps {
            output = try await rewrite(provider: provider, intent: intent, text: output, ollamaModel: ollamaModel)
        }
        return output
    }

    // A pipeline of recipes run in order, each step's output feeding the next.
    // Every step keeps its own tuned single-job prompt; a step that throws
    // stops the chain (the caller's text is never half-rewritten). stepRunner
    // exists so tests can drive the sequence without a live model.
    @MainActor
    static func rewriteChain(
        provider: RewriteProviderChoice,
        steps: [RewriteIntent],
        text: String,
        ollamaModel: String,
        stepRunner: (@MainActor (RewriteIntent, String) async throws -> String)? = nil,
        onProgress: (@MainActor (ChainProgress) -> Void)? = nil
    ) async throws -> String {
        guard !steps.isEmpty else { throw RewriteEngineError.emptyChain }
        let run = stepRunner ?? { intent, input in
            try await rewrite(provider: provider, intent: intent, text: input, ollamaModel: ollamaModel)
        }
        var output = text
        for (index, intent) in steps.enumerated() {
            let step = index + 1
            onProgress?(.starting(step: step, of: steps.count, intent: intent))
            output = try await run(intent, output)
            onProgress?(.stepFinished(step: step, of: steps.count, output: output))
        }
        return output
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
        provider: CleanupProviderChoice,
        openAIModel: OpenAIChatModel,
        ollamaModel: String,
        transcript: String
    ) async -> String? {
        guard DictationTranscript.isWorthCleaningUp(transcript) else { return nil }
        do {
            let output = try await runCleanup(
                provider: provider,
                openAIModel: openAIModel,
                ollamaModel: ollamaModel,
                transcript: transcript
            )
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return cleaned
        } catch {
            DebugLog.log("dictation cleanup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func runCleanup(
        provider: CleanupProviderChoice,
        openAIModel: OpenAIChatModel,
        ollamaModel: String,
        transcript: String
    ) async throws -> String {
        let directive = PromptComposer.dictationDirective(for: transcript)
        return switch provider {
        case .appleOnDevice:
            try await AppleIntelligenceEngine.rewrite(transcript, directive: directive)
        case .ollama:
            try await OllamaEngine().rewrite(transcript, directive: directive, model: ollamaModel)
        case .openAI:
            try await OpenAIChatEngine.rewrite(transcript, directive: directive, model: openAIModel)
        }
    }

    static func complete(
        provider: RewriteProviderChoice,
        context: String,
        surrounding: String? = nil,
        memory: String? = nil,
        styleProfile: String? = nil,
        ollamaModel: String
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.complete(
                context, surrounding: surrounding, memory: memory, styleProfile: styleProfile
            )
        case .ollama:
            try await OllamaEngine().complete(
                context, model: ollamaModel, surrounding: surrounding, memory: memory,
                styleProfile: styleProfile
            )
        }
    }
}
