import Foundation
import FoundationModels

enum AppleIntelligenceEngine {
    private static let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

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

    static func rewrite(_ text: String, intent: RewriteIntent) async throws -> String {
        guard model.isAvailable else {
            throw RewriteEngineError.modelUnavailable(status().detail)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: PromptComposer.systemInstructions
        )
        let response = try await session.respond(
            to: PromptComposer.userPrompt(intent: intent, text: text)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func complete(_ context: String) async throws -> String {
        guard model.isAvailable else {
            throw RewriteEngineError.modelUnavailable(status().detail)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: PromptComposer.completionSystemInstructions
        )
        let response = try await session.respond(
            to: PromptComposer.completionUserPrompt(context: context),
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 64)
        )
        let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw RewriteEngineError.invalidResponse
        }
        return output
    }
}
