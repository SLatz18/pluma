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
        provider: CleanupProviderChoice,
        openAIModel: OpenAIChatModel,
        transcript: String
    ) async -> String? {
        guard DictationTranscript.isWorthCleaningUp(transcript) else { return nil }
        do {
            let output = try await runCleanup(
                provider: provider, openAIModel: openAIModel, transcript: transcript
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
        transcript: String
    ) async throws -> String {
        switch provider {
        case .appleOnDevice:
            try await AppleIntelligenceEngine.rewrite(
                transcript, directive: PromptComposer.dictationDirective
            )
        case .openAI:
            try await OpenAIChatEngine.rewrite(
                transcript,
                directive: PromptComposer.dictationDirective,
                model: openAIModel
            )
        }
    }

    struct CleanupAttempt: Identifiable, Sendable {
        let provider: CleanupProviderChoice
        let label: String
        let output: String?
        let failure: String?
        let seconds: Double

        var id: String { label }
    }

    // Runs every candidate over the same transcript concurrently, so the outputs
    // are comparable and the timings reflect what the user would actually wait.
    static func compareCleanup(
        transcript: String,
        openAIModel: OpenAIChatModel
    ) async -> [CleanupAttempt] {
        let candidates: [(CleanupProviderChoice, String)] = [
            (.appleOnDevice, CleanupProviderChoice.appleOnDevice.title),
            (.openAI, openAIModel.title)
        ]

        return await withTaskGroup(of: (Int, CleanupAttempt).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let started = ContinuousClock.Instant.now
                    do {
                        let output = try await runCleanup(
                            provider: candidate.0,
                            openAIModel: openAIModel,
                            transcript: transcript
                        )
                        return (
                            index,
                            CleanupAttempt(
                                provider: candidate.0,
                                label: candidate.1,
                                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                                failure: nil,
                                seconds: elapsed(since: started)
                            )
                        )
                    } catch {
                        return (
                            index,
                            CleanupAttempt(
                                provider: candidate.0,
                                label: candidate.1,
                                output: nil,
                                failure: error.localizedDescription,
                                seconds: elapsed(since: started)
                            )
                        )
                    }
                }
            }

            var results: [(Int, CleanupAttempt)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.Instant.now - start
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
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
