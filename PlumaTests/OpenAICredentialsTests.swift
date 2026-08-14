import Foundation
import XCTest
@testable import Pluma

@MainActor
final class OpenAICredentialsTests: XCTestCase {
    func testSaveTrimsKeyPublishesReadyAndBumpsRevision() async {
        let store = CredentialMemoryStore()
        let credentials = makeCredentials(store: store, validation: .valid)

        await credentials.save("  sk-test-value\n")

        XCTAssertEqual(store.key, "sk-test-value")
        XCTAssertTrue(credentials.hasKey)
        XCTAssertEqual(credentials.state, .ready)
        XCTAssertEqual(credentials.revision, 1)
    }

    func testInvalidAndOfflineValidationRemainDistinct() async {
        let invalidStore = CredentialMemoryStore(key: "sk-invalid")
        let invalid = makeCredentials(
            store: invalidStore,
            validation: .invalid("Rejected by OpenAI")
        )
        await invalid.validate()
        XCTAssertEqual(invalid.state, .invalid("Rejected by OpenAI"))
        XCTAssertTrue(invalid.hasKey, "Validation must not silently delete a rejected key")

        let offlineStore = CredentialMemoryStore(key: "sk-offline")
        let offline = makeCredentials(
            store: offlineStore,
            validation: .offline("No network")
        )
        await offline.validate()
        XCTAssertEqual(offline.state, .offline("No network"))
        XCTAssertTrue(offline.hasKey, "Being offline must not be presented as an invalid key")
    }

    func testEndpointChangeInvalidatesValidationVerdict() async {
        let store = CredentialMemoryStore(key: "sk-ready")
        let credentials = makeCredentials(store: store, validation: .valid)
        await credentials.validate()
        XCTAssertEqual(credentials.state, .ready)

        // A verdict describes one destination; pointing elsewhere makes it stale.
        credentials.endpointBaseURLString = "https://other.example/openai/v1"
        XCTAssertEqual(credentials.state, .stored)

        await credentials.validate()
        XCTAssertEqual(credentials.state, .ready)

        credentials.useCustomEndpoint.toggle()
        XCTAssertEqual(credentials.state, .stored)
    }

    func testSaveFailureIsPublishedWithoutClaimingSuccess() async {
        let store = CredentialMemoryStore(saveError: CredentialFixtureError.saveDenied)
        let credentials = makeCredentials(store: store, validation: .valid)

        await credentials.save("sk-cannot-save")

        XCTAssertFalse(credentials.hasKey)
        XCTAssertEqual(
            credentials.state,
            .keychainFailure(CredentialFixtureError.saveDenied.localizedDescription)
        )
        XCTAssertEqual(credentials.revision, 0)
    }

    func testDeleteFailurePreservesPresenceAndPublishesError() {
        let store = CredentialMemoryStore(
            key: "sk-existing",
            clearError: CredentialFixtureError.deleteDenied
        )
        let credentials = makeCredentials(store: store, validation: .valid)

        credentials.remove()

        XCTAssertTrue(credentials.hasKey)
        XCTAssertEqual(
            credentials.state,
            .keychainFailure(CredentialFixtureError.deleteDenied.localizedDescription)
        )
        XCTAssertEqual(credentials.revision, 0)
    }

    func testValidationHTTPAndNetworkClassification() {
        XCTAssertEqual(OpenAICredentialValidator.classify(statusCode: 200), .valid)
        XCTAssertEqual(
            OpenAICredentialValidator.classify(statusCode: 401),
            .invalid("OpenAI rejected this key. Check the key and its project access.")
        )

        let offline = OpenAICredentialValidator.classify(
            error: URLError(.notConnectedToInternet)
        )
        guard case .offline = offline else {
            return XCTFail("A network outage must remain distinct from an invalid credential")
        }

        let service = OpenAICredentialValidator.classify(statusCode: 503)
        guard case .unavailable = service else {
            return XCTFail("A service outage must not be presented as an invalid credential")
        }
    }

    /// Isolated defaults are load-bearing: the test host is the app itself, so
    /// `.standard` here is the user's real preference domain — a credentials
    /// object writing endpoint settings through it would edit live settings.
    private func makeCredentials(
        store: CredentialMemoryStore,
        validation: OpenAICredentialValidation,
        function: String = #function
    ) -> OpenAICredentials {
        let suite = "OpenAICredentialsTests.\(function)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return OpenAICredentials(
            initialHasKey: store.hasKey,
            defaults: defaults,
            hasStoredKey: { store.hasKey },
            keyProvider: { store.key },
            saveKey: { try store.save($0) },
            clearKey: { try store.clear() },
            validator: { _ in validation }
        )
    }
}

private final class CredentialMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?
    private let saveError: (any Error)?
    private let clearError: (any Error)?

    init(
        key: String? = nil,
        saveError: (any Error)? = nil,
        clearError: (any Error)? = nil
    ) {
        storedKey = key
        self.saveError = saveError
        self.clearError = clearError
    }

    var key: String? {
        lock.withLock { storedKey }
    }

    var hasKey: Bool { key != nil }

    func save(_ value: String) throws {
        if let saveError { throw saveError }
        lock.withLock { storedKey = value }
    }

    func clear() throws {
        if let clearError { throw clearError }
        lock.withLock { storedKey = nil }
    }
}

private enum CredentialFixtureError: LocalizedError {
    case saveDenied
    case deleteDenied

    var errorDescription: String? {
        switch self {
        case .saveDenied: "Keychain refused the test save."
        case .deleteDenied: "Keychain refused the test delete."
        }
    }
}
