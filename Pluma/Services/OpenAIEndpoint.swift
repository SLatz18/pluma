import Foundation

/// Where every OpenAI-schema request goes. One base URL serves transcription,
/// cleanup, speech, and the model catalog: api.openai.com by default, or a
/// user-configured OpenAI-compatible gateway. The API key is the same either
/// way — one credential, one destination.
enum OpenAIEndpoint {
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    static func baseURL(from defaults: UserDefaults = .standard) -> URL {
        customBaseURL(from: defaults) ?? defaultBaseURL
    }

    static func customBaseURL(from defaults: UserDefaults = .standard) -> URL? {
        guard Preferences.cloudUseCustomEndpoint(from: defaults) else { return nil }
        return validatedBaseURL(Preferences.cloudBaseURLString(from: defaults))
    }

    static func isCustom(in defaults: UserDefaults = .standard) -> Bool {
        customBaseURL(from: defaults) != nil
    }

    /// Accepts only what a request can actually use: https with a host.
    static func validatedBaseURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }

    /// The base may carry a path prefix (many gateways serve `/openai/v1`),
    /// with or without a trailing slash — preserve it and append the API path.
    static func url(_ path: String, from defaults: UserDefaults = .standard) -> URL {
        baseURL(from: defaults).appendingPathComponent(path)
    }

    /// What data-path copy should call the destination, so labels stay truthful
    /// when the cloud path points somewhere other than OpenAI.
    static func destinationName(from defaults: UserDefaults = .standard) -> String {
        isCustom(in: defaults) ? "your endpoint" : "OpenAI"
    }

    /// The realtime API upgrades the same host to a websocket.
    static func websocketURL(_ pathAndQuery: String, from defaults: UserDefaults = .standard) -> URL {
        let base = baseURL(from: defaults)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        let split = pathAndQuery.split(separator: "?", maxSplits: 1)
        components.path = (components.path as NSString).appendingPathComponent(String(split[0]))
        components.query = split.count > 1 ? String(split[1]) : nil
        return components.url!
    }
}

/// Failure language for the cloud endpoint, kept as pure functions so the
/// pill, the settings surfaces, and the tests all agree on the copy.
enum CloudEndpointFailure {
    /// Gateways that mint per-user keys commonly rotate them on this cadence.
    static let keyExpiryHint: TimeInterval = 28 * 24 * 60 * 60

    static let unreachableMessage =
        "Couldn’t reach the endpoint — check your network or VPN."

    static func isConnectionFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .timedOut, .notConnectedToInternet,
             .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    /// Custom gateways reject with 401/403 when a rotated key goes stale, so
    /// an old save date earns the expiry hint; everything else passes through
    /// the OpenAI-compatible error envelope.
    static func describe(
        status: Int,
        data: Data,
        isCustomEndpoint: Bool,
        keySavedAt: Date?,
        now: Date = Date()
    ) -> String {
        guard isCustomEndpoint, status == 401 || status == 403 else {
            return OpenAIErrorBody.describe(status: status, data: data)
        }
        if let keySavedAt, now.timeIntervalSince(keySavedAt) >= keyExpiryHint {
            return "Your API key may have expired — custom endpoints often rotate keys. Re-enter it."
        }
        return "The endpoint rejected this API key. (HTTP \(status))"
    }
}
