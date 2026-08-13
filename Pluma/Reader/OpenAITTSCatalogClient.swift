import Foundation

/// Loads live OpenAI TTS options for Reader pickers.
///
/// Models come from `GET /v1/models` (filtered to TTS). OpenAI does not expose
/// a GET endpoint for built-in or custom voices, so voices remain a curated
/// catalog based on the speech endpoint's documented accepted values.
enum OpenAITTSCatalogClient {
    static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!

    struct Snapshot: Sendable {
        var models: [OpenAITTSCatalogOption]
        var modelsFromAPI: Bool
        var errorMessage: String?
    }

    static func fetch(
        session: URLSession = .shared,
        keyProvider: @Sendable () -> String? = { OpenAIKey.current }
    ) async -> Snapshot {
        guard let key = keyProvider() else {
            return Snapshot(
                models: OpenAITTSCatalog.fallbackModels,
                modelsFromAPI: false,
                errorMessage: "Add an OpenAI API key to refresh live model options."
            )
        }

        var models = OpenAITTSCatalog.fallbackModels
        var modelsFromAPI = false
        var errorMessage: String?

        do {
            let remoteIDs = try await listModelIDs(key: key, session: session)
            models = OpenAITTSCatalog.models(fromRemoteIDs: remoteIDs)
            modelsFromAPI = true
        } catch {
            errorMessage = error.localizedDescription
            DebugLog.log("openai tts models fetch failed: \(error.localizedDescription)", at: .quiet)
        }

        return Snapshot(
            models: models,
            modelsFromAPI: modelsFromAPI,
            errorMessage: errorMessage
        )
    }

    static func listModelIDs(
        key: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = OpenAIErrorBody.describe(status: http.statusCode, data: data)
            throw RewriteEngineError.modelUnavailable(detail)
        }

        let decoded = try JSONDecoder().decode(ModelsEnvelope.self, from: data)
        return decoded.data.map(\.id)
    }

    private struct ModelsEnvelope: Decodable {
        struct Item: Decodable {
            let id: String
        }

        let data: [Item]
    }
}
