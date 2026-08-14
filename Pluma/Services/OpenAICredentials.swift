import Foundation

enum OpenAICredentialValidation: Equatable, Sendable {
    case valid
    case invalid(String)
    case offline(String)
    case unavailable(String)
}

/// A deliberately small validation request. Listing models proves that the
/// bearer credential is accepted without sending user text, audio, or speech.
struct OpenAICredentialValidator: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String) async -> OpenAICredentialValidation {
        var request = URLRequest(url: OpenAIEndpoint.url("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable("OpenAI returned an unexpected response.")
            }
            return Self.classify(statusCode: http.statusCode)
        } catch {
            return Self.classify(error: error)
        }
    }

    static func classify(statusCode: Int) -> OpenAICredentialValidation {
        switch statusCode {
        case 200..<300:
            .valid
        case 401, 403:
            .invalid("OpenAI rejected this key. Check the key and its project access.")
        case 429:
            .unavailable("OpenAI accepted the request but rate limits or billing prevented a check.")
        case 500..<600:
            .unavailable("OpenAI is temporarily unavailable. The stored key was not changed.")
        default:
            .unavailable("OpenAI could not validate the key (HTTP \(statusCode)).")
        }
    }

    static func classify(error: any Error) -> OpenAICredentialValidation {
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .timedOut,
            .internationalRoamingOff
        ]
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return .offline("Couldn’t reach OpenAI. Check your connection; the stored key was not changed.")
        }
        return .unavailable("Couldn’t check the key: \(error.localizedDescription)")
    }
}

enum OpenAICredentialState: Equatable, Sendable {
    case missing
    case stored
    case checking
    case ready
    case invalid(String)
    case offline(String)
    case unavailable(String)
    case keychainFailure(String)

    var title: String {
        switch self {
        case .missing: "No key stored"
        case .stored: "Key stored"
        case .checking: "Checking key…"
        case .ready: "Connected"
        case .invalid: "Key rejected"
        case .offline: "Offline"
        case .unavailable: "Couldn’t check key"
        case .keychainFailure: "Keychain error"
        }
    }

    var detail: String {
        switch self {
        case .missing:
            "Add one key for OpenAI transcription, dictation cleanup, and Reader speech."
        case .stored:
            "Stored in Keychain. Check it before using an OpenAI feature."
        case .checking:
            "Validating with OpenAI without sending any user content."
        case .ready:
            "The stored key is accepted by OpenAI."
        case .invalid(let message),
             .offline(let message),
             .unavailable(let message),
             .keychainFailure(let message):
            message
        }
    }

    var needsValidation: Bool {
        self == .stored
    }
}

/// The sole observable credential state for every mounted UI surface.
/// Engines continue to read the secret directly from Keychain only at request
/// time; views observe this object and never keep their own presence booleans.
@MainActor
final class OpenAICredentials: ObservableObject {
    @Published private(set) var hasKey: Bool
    @Published private(set) var state: OpenAICredentialState
    @Published private(set) var revision = 0

    /// The one key pairs with one destination: api.openai.com by default, or a
    /// custom OpenAI-compatible base URL. Stored here so every settings surface
    /// binds to the same value; empty string means the default.
    @Published var endpointBaseURLString: String = Preferences.cloudBaseURLString() {
        didSet {
            guard endpointBaseURLString != oldValue else { return }
            Preferences.setCloudBaseURLString(endpointBaseURLString)
            revision &+= 1
        }
    }

    var isEndpointCustom: Bool {
        OpenAIEndpoint.validatedBaseURL(endpointBaseURLString) != nil
    }

    var isEndpointEntryValid: Bool {
        endpointBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || OpenAIEndpoint.validatedBaseURL(endpointBaseURLString) != nil
    }

    var keySavedAt: Date? {
        _ = revision
        return Preferences.openAIKeySavedAt()
    }

    private let hasStoredKey: @MainActor () -> Bool
    private let keyProvider: @Sendable () -> String?
    private let saveKey: @MainActor (String) throws -> Void
    private let clearKey: @MainActor () throws -> Void
    private let validator: @Sendable (String) async -> OpenAICredentialValidation
    private var validationGeneration = 0

    convenience init() {
        self.init(
            initialHasKey: OpenAIKey.isPresent,
            hasStoredKey: { OpenAIKey.isPresent },
            keyProvider: { OpenAIKey.current },
            saveKey: { try OpenAIKey.save($0) },
            clearKey: { try OpenAIKey.clear() },
            validator: { await OpenAICredentialValidator().validate(apiKey: $0) }
        )
    }

    init(
        initialHasKey: Bool,
        initialState: OpenAICredentialState? = nil,
        hasStoredKey: @escaping @MainActor () -> Bool,
        keyProvider: @escaping @Sendable () -> String?,
        saveKey: @escaping @MainActor (String) throws -> Void,
        clearKey: @escaping @MainActor () throws -> Void,
        validator: @escaping @Sendable (String) async -> OpenAICredentialValidation
    ) {
        hasKey = initialHasKey
        state = initialState ?? (initialHasKey ? .stored : .missing)
        self.hasStoredKey = hasStoredKey
        self.keyProvider = keyProvider
        self.saveKey = saveKey
        self.clearKey = clearKey
        self.validator = validator
    }

    func save(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        validationGeneration &+= 1
        do {
            try saveKey(trimmed)
            hasKey = true
            state = .stored
            revision &+= 1
            await validate()
        } catch {
            hasKey = hasStoredKey()
            state = .keychainFailure(error.localizedDescription)
        }
    }

    func remove() {
        validationGeneration &+= 1
        do {
            try clearKey()
            hasKey = false
            state = .missing
            revision &+= 1
        } catch {
            hasKey = hasStoredKey()
            state = .keychainFailure(error.localizedDescription)
        }
    }

    func validate() async {
        guard hasKey else {
            state = .missing
            return
        }
        guard let key = keyProvider(), !key.isEmpty else {
            hasKey = hasStoredKey()
            state = hasKey
                ? .keychainFailure("The saved key could not be read from Keychain.")
                : .missing
            return
        }

        validationGeneration &+= 1
        let generation = validationGeneration
        state = .checking
        let result = await validator(key)
        guard generation == validationGeneration, hasKey else { return }

        switch result {
        case .valid:
            state = .ready
        case .invalid(let message):
            state = .invalid(message)
        case .offline(let message):
            state = .offline(message)
        case .unavailable(let message):
            state = .unavailable(message)
        }
    }

    /// Deterministic credential states let UI tests and screenshots exercise
    /// missing, valid, invalid, and offline UI without touching a real keychain.
    static func fixture(
        hasKey: Bool,
        state: OpenAICredentialState,
        validation: OpenAICredentialValidation = .valid
    ) -> OpenAICredentials {
        let store = OpenAIFixtureSecret(hasKey: hasKey)
        return OpenAICredentials(
            initialHasKey: hasKey,
            initialState: state,
            hasStoredKey: { store.hasKey },
            keyProvider: { store.key },
            saveKey: { store.save($0) },
            clearKey: { store.clear() },
            validator: { _ in validation }
        )
    }

    static func forCurrentProcess() -> OpenAICredentials {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "--pluma-ui-openai-state"),
              arguments.indices.contains(marker + 1)
        else { return OpenAICredentials() }

        switch arguments[marker + 1] {
        case "ready":
            return fixture(hasKey: true, state: .ready)
        case "invalid":
            return fixture(
                hasKey: true,
                state: .invalid("OpenAI rejected this test key."),
                validation: .invalid("OpenAI rejected this test key.")
            )
        case "offline":
            return fixture(
                hasKey: true,
                state: .offline("Couldn’t reach OpenAI in this test state."),
                validation: .offline("Couldn’t reach OpenAI in this test state.")
            )
        default:
            return fixture(hasKey: false, state: .missing)
        }
    }
}

private final class OpenAIFixtureSecret: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(hasKey: Bool) {
        value = hasKey ? "sk-pluma-ui-fixture" : nil
    }

    var key: String? {
        lock.withLock { value }
    }

    var hasKey: Bool { key != nil }

    func save(_ key: String) {
        lock.withLock { value = key }
    }

    func clear() {
        lock.withLock { value = nil }
    }
}
