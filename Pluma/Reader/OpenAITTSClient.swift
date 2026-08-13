import Foundation

enum OpenAITTSClient {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!

    static func synthesize(
        text: String,
        voiceID: String,
        modelID: String,
        speed: Double,
        session: URLSession = .shared
    ) async throws -> Data {
        guard let key = OpenAIKey.current else {
            throw OpenAITranscriptionError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(
            text: text,
            voiceID: voiceID,
            modelID: modelID,
            speed: speed
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = OpenAIErrorBody.describe(status: http.statusCode, data: data)
            DebugLog.log("openai tts failed: \(detail)", at: .quiet)
            throw RewriteEngineError.modelUnavailable(detail)
        }
        return data
    }

    static func requestBody(
        text: String,
        voiceID: String,
        modelID: String,
        speed: Double
    ) throws -> Data {
        let clampedSpeed = min(max(speed, 0.25), 4.0)
        return try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "input": text,
            "voice": voiceID,
            "response_format": "mp3",
            "speed": clampedSpeed
        ])
    }
}
