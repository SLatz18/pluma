import Foundation

enum RewriteRunner {
    static func rewrite(
        provider: RewriteProviderChoice,
        intent: RewriteIntent,
        text: String,
        ollamaModel: String,
        profile: StyleProfile = .none
    ) async throws -> String {
        switch provider {
        case .appleIntelligence:
            try await AppleIntelligenceEngine.rewrite(text, intent: intent, profile: profile)
        case .ollama:
            try await OllamaEngine().rewrite(
                text,
                intent: intent,
                model: ollamaModel,
                profile: profile
            )
        }
    }
}
