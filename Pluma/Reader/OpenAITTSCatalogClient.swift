import Foundation

/// Loads live OpenAI TTS options for Reader pickers.
///
/// Models come from `GET /v1/models` (filtered to TTS). Built-in voices have no
/// list endpoint, so those stay curated; this client also best-effort probes
/// `GET /v1/audio/voices` for account custom voices when the org supports them.
enum OpenAITTSCatalogClient {
    static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!
    static let voicesEndpoint = URL(string: "https://api.openai.com/v1/audio/voices")!

    struct Snapshot: Sendable {
        var models: [OpenAITTSCatalogOption]
        var customVoices: [OpenAITTSCatalogOption]
        var modelsFromAPI: Bool
        var customVoicesFromAPI: Bool
        var errorMessage: String?
    }

    static func fetch(
        session: URLSession = .shared,
        keyProvider: @Sendable () -> String? = { OpenAIKey.current }
    ) async -> Snapshot {
        guard let key = keyProvider() else {
            return Snapshot(
                models: OpenAITTSCatalog.fallbackModels,
                customVoices: [],
                modelsFromAPI: false,
                customVoicesFromAPI: false,
                errorMessage: "Add an OpenAI API key to refresh live model options."
            )
        }

        var models = OpenAITTSCatalog.fallbackModels
        var modelsFromAPI = false
        var customVoices: [OpenAITTSCatalogOption] = []
        var customVoicesFromAPI = false
        var errorMessage: String?

        do {
            let remoteIDs = try await listModelIDs(key: key, session: session)
            models = OpenAITTSCatalog.models(fromRemoteIDs: remoteIDs)
            modelsFromAPI = true
        } catch {
            errorMessage = error.localizedDescription
            DebugLog.log("openai tts models fetch failed: \(error.localizedDescription)", at: .quiet)
        }

        do {
            customVoices = try await listCustomVoices(key: key, session: session)
            customVoicesFromAPI = true
        } catch {
            // Custom voices are enterprise-only and the list route is still
            // evolving — keep built-ins and ignore a missing endpoint.
            DebugLog.log("openai tts custom voices fetch skipped: \(error.localizedDescription)", at: .verbose)
        }

        return Snapshot(
            models: models,
            customVoices: customVoices,
            modelsFromAPI: modelsFromAPI,
            customVoicesFromAPI: customVoicesFromAPI,
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

    static func listCustomVoices(
        key: String,
        session: URLSession = .shared
    ) async throws -> [OpenAITTSCatalogOption] {
        var request = URLRequest(url: voicesEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RewriteEngineError.modelUnavailable("OpenAI returned a non-HTTP response")
        }
        // 404/405 mean the account or API shape doesn't expose listing yet.
        if http.statusCode == 404 || http.statusCode == 405 {
            return []
        }
        if http.statusCode != 200 {
            let detail = OpenAIErrorBody.describe(status: http.statusCode, data: data)
            throw RewriteEngineError.modelUnavailable(detail)
        }

        if let list = try? JSONDecoder().decode(VoicesEnvelope.self, from: data) {
            return list.data.map { voice in
                OpenAITTSCatalogOption(
                    id: voice.id,
                    title: voice.name.isEmpty ? OpenAITTSCatalog.displayTitle(forVoiceID: voice.id) : voice.name,
                    detail: "Custom voice from your OpenAI account.",
                    kind: .customVoice
                )
            }
        }
        if let single = try? JSONDecoder().decode(VoiceDTO.self, from: data) {
            return [
                OpenAITTSCatalogOption(
                    id: single.id,
                    title: single.name.isEmpty ? OpenAITTSCatalog.displayTitle(forVoiceID: single.id) : single.name,
                    detail: "Custom voice from your OpenAI account.",
                    kind: .customVoice
                )
            ]
        }
        return []
    }

    private struct ModelsEnvelope: Decodable {
        struct Item: Decodable {
            let id: String
        }

        let data: [Item]
    }

    private struct VoicesEnvelope: Decodable {
        let data: [VoiceDTO]
    }

    private struct VoiceDTO: Decodable {
        let id: String
        let name: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
        }
    }
}
