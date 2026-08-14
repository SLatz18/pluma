import Foundation

enum OpenAIChatEngine {
    private static var endpoint: URL { OpenAIEndpoint.url("responses") }

    static func rewrite(
        _ text: String,
        directive: String,
        model: OpenAIChatModel,
        session: URLSession = .shared
    ) async throws -> String {
        try await respond(
            body: payload(text: text, directive: directive, model: model),
            session: session
        )
    }

    // The previously missing OpenAI generation path: composing a fresh reply
    // rather than editing supplied text. Same Responses call, different prompt.
    static func draftReply(
        intent: String,
        conversation: String?,
        model: OpenAIChatModel,
        memory: String? = nil,
        styleProfile: String? = nil,
        session: URLSession = .shared
    ) async throws -> String {
        try await respond(
            body: [
                "model": model.rawValue,
                "instructions": PromptComposer.draftReplyInstructions(styleProfile: styleProfile),
                "input": PromptComposer.draftReplyUserPrompt(
                    intent: intent, conversation: conversation, memory: memory
                ),
                "reasoning": ["effort": "none"],
                "store": false
            ],
            session: session
        )
    }

    private static func respond(
        body: [String: Any],
        session: URLSession
    ) async throws -> String {
        guard let key = OpenAIKey.current else {
            throw RewriteEngineError.modelUnavailable("Add an OpenAI API key in settings")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = OpenAIErrorBody.describe(status: http.statusCode, data: data)
            DebugLog.log("openai request failed: \(detail)", at: .quiet)
            throw RewriteEngineError.modelUnavailable(detail)
        }

        let decoded = try JSONDecoder().decode(ResponsesReply.self, from: data)
        let output = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw RewriteEngineError.invalidResponse }
        return output
    }

    // Reasoning effort is none deliberately: this is a mechanical edit in the
    // middle of a keystroke, and a model that deliberates first is a model the
    // user waits on.
    static func payload(
        text: String, directive: String, model: OpenAIChatModel
    ) -> [String: Any] {
        [
            "model": model.rawValue,
            "instructions": PromptComposer.systemInstructions,
            "input": PromptComposer.userPrompt(directive: directive, text: text),
            "reasoning": ["effort": "none"],
            "store": false
        ]
    }

    // The Responses API nests output text a few levels down, and the shape
    // carries reasoning items we don't ask for but should tolerate.
    private struct ResponsesReply: Decodable {
        struct Output: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }

            let type: String
            let content: [Content]?
        }

        let outputText: String?
        let output: [Output]?

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
            case output
        }

        var text: String {
            if let outputText, !outputText.isEmpty { return outputText }
            guard let output else { return "" }
            return output
                .filter { $0.type == "message" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap(\.text)
                .joined()
        }
    }
}
