import Foundation

/// Loads live OpenAI TTS options for Reader pickers.
///
/// Models come from `GET /v1/models` (filtered to TTS). OpenAI does not expose
/// a GET endpoint for built-in or custom voices, so voices remain a curated
/// catalog based on the speech endpoint's documented accepted values.
enum OpenAITTSCatalogClient {
    static var modelsEndpoint: URL { OpenAIEndpoint.url("models") }

    struct Snapshot: Sendable {
        var models: [OpenAITTSCatalogOption]
        var modelsFromAPI: Bool
        var errorMessage: String?
    }

    static func fetch(
        endpoint: URL = modelsEndpoint,
        session: URLSession = .shared,
        keyProvider: @Sendable () -> String? = { OpenAIKey.current },
        missingKeyMessage: String = "Add an OpenAI API key to refresh live model options."
    ) async -> Snapshot {
        guard let key = keyProvider() else {
            return Snapshot(
                models: OpenAITTSCatalog.fallbackModels,
                modelsFromAPI: false,
                errorMessage: missingKeyMessage
            )
        }

        var models = OpenAITTSCatalog.fallbackModels
        var modelsFromAPI = false
        var errorMessage: String?

        do {
            let remoteIDs = try await listModelIDs(endpoint: endpoint, key: key, session: session)
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
        endpoint: URL = modelsEndpoint,
        key: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        var request = URLRequest(url: endpoint)
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
