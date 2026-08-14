import Foundation

enum OpenAITTSClient {
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

        var request = URLRequest(url: OpenAIEndpoint.url("audio/speech"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(
            text: text,
            voiceID: voiceID,
            modelID: modelID,
            speed: speed
        )

        let isCustom = OpenAIEndpoint.isCustom()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where isCustom && CloudEndpointFailure.isConnectionFailure(error) {
            DebugLog.log("tts endpoint unreachable: \(error.code.rawValue)", at: .quiet)
            throw RewriteEngineError.modelUnavailable(CloudEndpointFailure.unreachableMessage)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = CloudEndpointFailure.describe(
                status: http.statusCode,
                data: data,
                isCustomEndpoint: isCustom,
                keySavedAt: Preferences.openAIKeySavedAt()
            )
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
