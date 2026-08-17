import Foundation

enum ChainProgress {
    case starting(step: Int, of: Int, intent: RewriteIntent)
    case stepFinished(step: Int, of: Int, output: String)
}

// Test seam: when installed, completion and dictation-cleanup requests are
// handed to the spy with the exact composed instructions the provider engines
// would send, instead of reaching a live model. Production never sets this.
@MainActor
protocol AIRequestSpying: AnyObject, Sendable {
    func completionRequested(instructions: String, prompt: String) async throws -> String
    func cleanupRequested(directive: String, transcript: String) async throws -> String
    func rewriteRequested(system: String, prompt: String) async throws -> String
}

enum RewriteRunner {
    @MainActor static var requestSpy: (any AIRequestSpying)?

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
        if let spy = await MainActor.run(body: { requestSpy }) {
            return try await spy.rewriteRequested(
                system: PromptComposer.systemInstructions,
                prompt: PromptComposer.userPrompt(directive: directive, text: text)
            )
        }
        return switch provider {
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
        transcript: String,
        directives: [CleanupDirective] = CleanupDirective.defaultChain
    ) async -> String? {
        guard DictationTranscript.isWorthCleaningUp(transcript) else { return nil }
        do {
            let output = try await runCleanup(
                provider: provider,
                openAIModel: openAIModel,
                ollamaModel: ollamaModel,
                transcript: transcript,
                directives: directives
            )
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return cleaned
        } catch {
            DebugLog.log("dictation cleanup failed: \(error.localizedDescription)", at: .quiet)
            return nil
        }
    }

    static func runCleanup(
        provider: CleanupProviderChoice,
        openAIModel: OpenAIChatModel,
        ollamaModel: String,
        transcript: String,
        directives: [CleanupDirective] = CleanupDirective.defaultChain
    ) async throws -> String {
        let directive = PromptComposer.dictationDirective(for: transcript, directives: directives)
        if let spy = await MainActor.run(body: { requestSpy }) {
            return try await spy.cleanupRequested(directive: directive, transcript: transcript)
        }
        return switch provider {
        case .appleOnDevice:
            try await AppleIntelligenceEngine.rewrite(transcript, directive: directive)
        case .ollama:
            try await OllamaEngine().rewrite(transcript, directive: directive, model: ollamaModel)
        case .openAI:
            try await OpenAIChatEngine.rewrite(transcript, directive: directive, model: openAIModel)
        }
    }

    // A model that returns only whitespace has told us nothing, and writing
    // that back would silently erase the writer's selection. Fail instead.
    static func validatedOutput(_ output: String) throws -> String {
        // Chat-tuned models wrap an edit in commentary even when the prompt
        // forbids it, so parse defensively before this reaches the writer's
        // document (issue #39).
        let cleaned = RewriteOutputSanitizer.sanitize(output)
        guard !cleaned.isEmpty else {
            throw RewriteEngineError.invalidResponse
        }
        return cleaned
    }

    static func complete(
        provider: RewriteProviderChoice,
        context: String,
        surrounding: String? = nil,
        conversation: String? = nil,
        memory: String? = nil,
        styleProfile: String? = nil,
        directives: [CompletionDirective] = CompletionDirective.defaultChain,
        ollamaModel: String
    ) async throws -> String {
        if let spy = await MainActor.run(body: { requestSpy }) {
            // Both engines send exactly these two composed strings as the
            // system instructions and user prompt, so capturing them here is
            // faithful to the real request.
            return try await spy.completionRequested(
                instructions: PromptComposer.completionInstructions(
                    styleProfile: styleProfile, directives: directives
                ),
                prompt: PromptComposer.completionUserPrompt(
                    context: context, surrounding: surrounding,
                    conversation: conversation, memory: memory
                )
            )
        }
        switch provider {
        case .appleIntelligence:
            return try await AppleIntelligenceEngine.complete(
                context, surrounding: surrounding, conversation: conversation,
                memory: memory, styleProfile: styleProfile, directives: directives
            )
        case .ollama:
            return try await OllamaEngine().complete(
                context, model: ollamaModel, surrounding: surrounding,
                conversation: conversation, memory: memory, styleProfile: styleProfile,
                directives: directives
            )
        }
    }

    // Composes a full reply from the visible thread plus the user's spoken or
    // typed intent. Rides the cleanup provider choice deliberately: drafting
    // happens at the end of a dictation, so the model the user picked for
    // "after you speak" is the model that speaks for them.
    static func draftReply(
        provider: CleanupProviderChoice,
        openAIModel: OpenAIChatModel,
        ollamaModel: String,
        intent: String,
        conversation: String?,
        memory: String? = nil,
        styleProfile: String? = nil
    ) async throws -> String {
        let output = switch provider {
        case .appleOnDevice:
            try await AppleIntelligenceEngine.draftReply(
                intent: intent, conversation: conversation,
                memory: memory, styleProfile: styleProfile
            )
        case .ollama:
            try await OllamaEngine().draftReply(
                intent: intent, conversation: conversation, model: ollamaModel,
                memory: memory, styleProfile: styleProfile
            )
        case .openAI:
            try await OpenAIChatEngine.draftReply(
                intent: intent, conversation: conversation, model: openAIModel,
                memory: memory, styleProfile: styleProfile
            )
        }
        return try validatedOutput(output)
    }
}
