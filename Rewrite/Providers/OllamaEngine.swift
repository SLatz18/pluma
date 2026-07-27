import Foundation

struct OllamaEngine: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func availableModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url, timeoutInterval: RewriteTimeouts.ollamaDiscovery)
        request.httpMethod = "GET"

        let (data, response) = try await perform(request)
        try validate(response, data: data)

        return try Self.decodeModels(from: data)
    }

    func rewrite(_ text: String, directive: String, model: String) async throws -> String {
        guard !model.isEmpty else {
            throw RewriteEngineError.noOllamaModels
        }
        guard try await availableModels().contains(model) else {
            throw RewriteEngineError.cloudOllamaModel
        }

        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url, timeoutInterval: RewriteTimeouts.modelRequest)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.makeChatRequestBody(
            text: text,
            intent: intent,
            model: model
        )

        let (data, response) = try await perform(request)
        try validate(response, data: data)

        return try Self.decodeRewrite(from: data, original: text)
    }

    static func makeChatRequestBody(
        text: String,
        intent: RewriteIntent,
        model: String
    ) throws -> Data {
        try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: PromptComposer.systemInstructions),
                    .init(
                        role: "user",
                        content: PromptComposer.userPrompt(directive: directive, text: text)
                    )
                ],
                stream: false,
                options: .init(seed: 0, temperature: 0)
            )
        )
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
            LoopbackPolicy.allows(httpResponse.url),
            (200..<300).contains(httpResponse.statusCode)
        else {
            if
                let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                !payload.error.isEmpty
            {
                throw RewriteEngineError.providerFailure("Ollama: \(payload.error)")
            }
            throw RewriteEngineError.providerFailure("Ollama returned an unsuccessful response.")
        }
    }
}

private extension OllamaEngine {
    struct ModelListResponse: Decodable {
        let models: [Model]
    }

    struct Model: Decodable {
        let name: String
        let size: Int64
        let digest: String
        let details: ModelDetails

        var isStoredLocally: Bool {
            let normalizedName = name.lowercased()
            return size > 0
                && !digest.isEmpty
                && !details.format.isEmpty
                && !normalizedName.contains(":cloud")
                && !normalizedName.hasSuffix("-cloud")
        }
    }

    struct ModelDetails: Decodable {
        let format: String
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

    struct ErrorResponse: Decodable {
        let error: String
    }
}

enum LoopbackPolicy {
    static func allows(_ url: URL?) -> Bool {
        guard
            let url,
            let scheme = url.scheme?.lowercased(),
            let host = url.host?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }

        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

private final class LoopbackOnlyRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let shared = LoopbackOnlyRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(LoopbackPolicy.allows(request.url) ? request : nil)
    }
}
