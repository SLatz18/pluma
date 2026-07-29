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

    func rewrite(_ text: String, directive: String, model: String) async throws -> String {
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
                    .init(role: "system", content: PromptComposer.systemInstructions),
                    .init(
                        role: "user",
                        content: PromptComposer.userPrompt(directive: directive, text: text)
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

    func complete(
        _ context: String,
        model: String,
        surrounding: String? = nil,
        memory: String? = nil,
        styleProfile: String? = nil
    ) async throws -> String {
        guard !model.isEmpty else {
            throw RewriteEngineError.noOllamaModels
        }

        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(
                        role: "system",
                        content: PromptComposer.completionInstructions(styleProfile: styleProfile)
                    ),
                    .init(
                        role: "user",
                        content: PromptComposer.completionUserPrompt(
                            context: context, surrounding: surrounding, memory: memory
                        )
                    )
                ],
                stream: false,
                options: .init(numPredict: 64, temperature: 0.3)
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
        var options: Options?

        struct Options: Encodable {
            let numPredict: Int
            let temperature: Double

            enum CodingKeys: String, CodingKey {
                case numPredict = "num_predict"
                case temperature
            }
        }
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ChatResponse: Decodable {
        let message: Message
    }
}
