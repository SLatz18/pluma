import Foundation

/// A selectable OpenAI TTS voice or model shown in Reader pickers.
///
/// Built-in voices come from OpenAI's documented speech set (no public list
/// endpoint exists for them). Models are preferentially loaded from
/// `GET /v1/models`, with this catalog as the offline fallback.
struct OpenAITTSCatalogOption: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case builtInVoice
        case customVoice
        case model
    }

    let id: String
    let title: String
    let detail: String
    let kind: Kind

    var isCustomVoice: Bool { kind == .customVoice }
}

enum OpenAITTSCatalog {
    static let defaultVoiceID = "nova"
    static let defaultModelID = "tts-1-hd"

    /// Voices supported by `tts-1` / `tts-1-hd`.
    static let classicModelVoiceIDs: Set<String> = [
        "alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"
    ]

    /// Full built-in set for `gpt-4o-mini-tts` and its snapshots.
    static let builtInVoiceIDs: [String] = [
        "alloy", "ash", "ballad", "coral", "echo", "fable",
        "nova", "onyx", "sage", "shimmer", "verse", "marin", "cedar"
    ]

    static let fallbackModelIDs: [String] = [
        "tts-1",
        "tts-1-hd",
        "gpt-4o-mini-tts"
    ]

    static var builtInVoices: [OpenAITTSCatalogOption] {
        builtInVoiceIDs.map { id in
            OpenAITTSCatalogOption(
                id: id,
                title: displayTitle(forVoiceID: id),
                detail: classicModelVoiceIDs.contains(id)
                    ? "Works with all OpenAI TTS models."
                    : "Requires GPT-4o mini TTS.",
                kind: .builtInVoice
            )
        }
    }

    static var fallbackModels: [OpenAITTSCatalogOption] {
        fallbackModelIDs.map { id in
            OpenAITTSCatalogOption(
                id: id,
                title: displayTitle(forModelID: id),
                detail: detail(forModelID: id),
                kind: .model
            )
        }
    }

    static func isTTSModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        if lower.hasPrefix("tts-") { return true }
        if lower.contains("tts") { return true }
        return false
    }

    static func voices(
        compatibleWithModel modelID: String,
        customVoices: [OpenAITTSCatalogOption] = []
    ) -> [OpenAITTSCatalogOption] {
        let builtIn: [OpenAITTSCatalogOption]
        if usesClassicVoiceSet(modelID: modelID) {
            builtIn = builtInVoices.filter { classicModelVoiceIDs.contains($0.id) }
        } else {
            builtIn = builtInVoices
        }
        return builtIn + customVoices
    }

    static func usesClassicVoiceSet(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "tts-1" || lower.hasPrefix("tts-1-") || lower == "tts-1-hd"
    }

    static func resolveVoiceID(
        preferred: String,
        available: [OpenAITTSCatalogOption]
    ) -> String {
        if available.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if available.contains(where: { $0.id == defaultVoiceID }) {
            return defaultVoiceID
        }
        return available.first?.id ?? defaultVoiceID
    }

    static func resolveModelID(
        preferred: String,
        available: [OpenAITTSCatalogOption]
    ) -> String {
        if available.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if available.contains(where: { $0.id == defaultModelID }) {
            return defaultModelID
        }
        return available.first?.id ?? defaultModelID
    }

    static func displayTitle(forVoiceID id: String) -> String {
        if id.hasPrefix("voice_") {
            return "Custom voice"
        }
        return id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func displayTitle(forModelID id: String) -> String {
        switch id {
        case "tts-1": return "TTS-1"
        case "tts-1-hd": return "TTS-1 HD"
        case "gpt-4o-mini-tts": return "GPT-4o mini TTS"
        default:
            if id.hasPrefix("gpt-4o-mini-tts-") {
                return "GPT-4o mini TTS (\(String(id.dropFirst("gpt-4o-mini-tts-".count))))"
            }
            return id
        }
    }

    static func detail(forModelID id: String) -> String {
        switch id {
        case "tts-1":
            return "Fastest and cheapest."
        case "tts-1-hd":
            return "Higher fidelity system voice."
        case let value where value.hasPrefix("gpt-4o-mini-tts"):
            return "Newest OpenAI speech model."
        default:
            return "OpenAI text-to-speech model."
        }
    }

    static func models(fromRemoteIDs ids: [String]) -> [OpenAITTSCatalogOption] {
        var seen = Set<String>()
        let filtered = ids.filter { id in
            guard isTTSModelID(id), seen.insert(id).inserted else { return false }
            return true
        }
        .sorted { lhs, rhs in
            rank(forModelID: lhs) < rank(forModelID: rhs)
        }
        let options = filtered.map { id in
            OpenAITTSCatalogOption(
                id: id,
                title: displayTitle(forModelID: id),
                detail: detail(forModelID: id),
                kind: .model
            )
        }
        return options.isEmpty ? fallbackModels : options
    }

    private static func rank(forModelID id: String) -> (Int, String) {
        switch id {
        case "tts-1": return (0, id)
        case "tts-1-hd": return (1, id)
        case "gpt-4o-mini-tts": return (2, id)
        case let value where value.hasPrefix("gpt-4o-mini-tts-"): return (3, id)
        default: return (10, id)
        }
    }
}
