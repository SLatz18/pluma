import Foundation

/// Speech synthesis against a user-configured OpenAI-compatible endpoint.
/// Same request shape as `OpenAITTSClient`; only the destination, the
/// credential, and the failure language differ.
enum CustomTTSClient {
    static func synthesize(
        text: String,
        voiceID: String,
        modelID: String,
        speed: Double,
        session: URLSession = .shared
    ) async throws -> Data {
        guard let base = CustomTTSEndpoint.baseURL() else {
            throw RewriteEngineError.modelUnavailable(CustomEndpointFailure.missingBaseURLMessage)
        }
        guard let key = CustomTTSKey.current else {
            throw RewriteEngineError.modelUnavailable(CustomEndpointFailure.missingKeyMessage)
        }

        var request = URLRequest(url: CustomTTSEndpoint.speechURL(base: base))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try OpenAITTSClient.requestBody(
            text: text,
            voiceID: voiceID,
            modelID: modelID,
            speed: speed
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where CustomEndpointFailure.isConnectionFailure(error) {
            DebugLog.log("custom tts unreachable: \(error.code.rawValue)", at: .quiet)
            throw RewriteEngineError.modelUnavailable(CustomEndpointFailure.unreachableMessage)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = CustomEndpointFailure.describe(
                status: http.statusCode,
                data: data,
                keySavedAt: Preferences.customTTSKeySavedAt()
            )
            DebugLog.log("custom tts failed: \(detail)", at: .quiet)
            throw RewriteEngineError.modelUnavailable(detail)
        }
        return data
    }
}

/// Failure language for the custom endpoint, kept as pure functions so the
/// pill, the settings surfaces, and the tests all agree on the copy.
enum CustomEndpointFailure {
    /// Gateways that mint per-user keys commonly rotate them on this cadence.
    static let keyExpiryHint: TimeInterval = 28 * 24 * 60 * 60

    static let missingBaseURLMessage =
        "Add your custom endpoint's base URL in settings"
    static let missingKeyMessage =
        "Add your custom endpoint API key in settings"
    static let unreachableMessage =
        "Couldn’t reach the custom endpoint — check your network or VPN."

    static func isConnectionFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .timedOut, .notConnectedToInternet,
             .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    static func describe(
        status: Int,
        data: Data,
        keySavedAt: Date?,
        now: Date = Date()
    ) -> String {
        guard status == 401 || status == 403 else {
            return OpenAIErrorBody.describe(status: status, data: data)
        }
        if let keySavedAt, now.timeIntervalSince(keySavedAt) >= keyExpiryHint {
            return "Your API key may have expired — custom endpoints often rotate keys. Re-enter it."
        }
        return "The endpoint rejected this API key. (HTTP \(status))"
    }
}
