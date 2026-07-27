import Foundation

struct OllamaEngine: Sendable {
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    func availableModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        let payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return payload.models.map(\.name).sorted()
    }

    func rewrite(
        _ text: String,
        intent: RewriteIntent,
        model: String,
        profile: StyleProfile = .none
    ) async throws -> String {
        guard !model.isEmpty else {
            throw RewriteEngineError.noOllamaModels
        }

        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(
                        role: "system",
                        content: PromptComposer.systemInstructions(for: profile)
                    ),
                    .init(
                        role: "user",
                        content: PromptComposer.userPrompt(intent: intent, text: text)
                    )
                ],
                stream: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        let payload = try JSONDecoder().decode(ChatResponse.self, from: data)
        let output = payload.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw RewriteEngineError.invalidResponse
        }
        return output
    }

    private func validate(_ response: URLResponse) throws {
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw RewriteEngineError.invalidResponse
        }
    }
}

private extension OllamaEngine {
    struct ModelListResponse: Decodable {
        let models: [Model]
    }

    struct Model: Decodable {
        let name: String
    }

    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ChatResponse: Decodable {
        let message: Message
    }
}
