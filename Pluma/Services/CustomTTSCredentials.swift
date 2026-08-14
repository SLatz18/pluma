import Foundation

/// Where requests to the custom OpenAI-compatible endpoint go. The base URL is
/// user-supplied configuration, not a secret, so it lives in defaults.
enum CustomTTSEndpoint {
    static func baseURL(from defaults: UserDefaults = .standard) -> URL? {
        validatedBaseURL(Preferences.customTTSBaseURLString(from: defaults))
    }

    /// Accepts only what a speech request can actually use: https with a host.
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
    /// with or without a trailing slash — preserve it and append the OpenAI
    /// speech path.
    static func speechURL(base: URL) -> URL {
        base.appendingPathComponent("audio/speech")
    }
}

/// The sole observable credential/config state for the custom endpoint, shared
/// by every mounted UI surface — same role `OpenAICredentials` plays for the
/// OpenAI key. No remote validation in v1: there is no endpoint we can assume
/// exists on an arbitrary gateway, so readiness is "has a key and a valid URL".
@MainActor
final class CustomTTSCredentials: ObservableObject {
    @Published private(set) var hasKey: Bool
    @Published private(set) var keySavedAt: Date?
    @Published var baseURLString: String {
        didSet {
            Preferences.setCustomTTSBaseURLString(baseURLString, to: defaults)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasKey = CustomTTSKey.isPresent
        keySavedAt = Preferences.customTTSKeySavedAt(from: defaults)
        baseURLString = Preferences.customTTSBaseURLString(from: defaults)
    }

    var isBaseURLValid: Bool {
        CustomTTSEndpoint.validatedBaseURL(baseURLString) != nil
    }

    var isReady: Bool { hasKey && isBaseURLValid }

    func save(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try CustomTTSKey.save(trimmed, to: defaults)
            hasKey = true
            keySavedAt = Preferences.customTTSKeySavedAt(from: defaults)
        } catch {
            DebugLog.log("custom tts key save failed: \(error.localizedDescription)", at: .quiet)
        }
    }

    func removeKey() {
        do {
            try CustomTTSKey.clear(from: defaults)
            hasKey = false
            keySavedAt = nil
        } catch {
            DebugLog.log("custom tts key remove failed: \(error.localizedDescription)", at: .quiet)
        }
    }
}
