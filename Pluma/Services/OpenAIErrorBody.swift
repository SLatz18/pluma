import Foundation

// A bare status code doesn't distinguish a spent quota from real throttling, and
// both arrive as 429. OpenAI puts the distinction in the response body, so the
// body is what gets reported.
enum OpenAIErrorBody {
    static func describe(status: Int, data: Data) -> String {
        guard
            let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
            let error = decoded.error,
            let message = error.message,
            !message.isEmpty
        else {
            return "OpenAI returned HTTP \(status)"
        }

        if let code = error.code, !code.isEmpty {
            return "\(message) (HTTP \(status), \(code))"
        }
        return "\(message) (HTTP \(status))"
    }

    private struct Envelope: Decodable {
        struct Body: Decodable {
            let message: String?
            let code: String?
            let type: String?
        }

        let error: Body?
    }
}
