import XCTest
@testable import Pluma

final class CustomTTSTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CustomTTSTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Base URL validation

    func testValidHTTPSBaseURLIsAccepted() {
        XCTAssertNotNil(CustomTTSEndpoint.validatedBaseURL("https://example.com/openai/v1"))
        XCTAssertNotNil(CustomTTSEndpoint.validatedBaseURL("  https://example.com  "))
    }

    func testInvalidBaseURLsAreRejected() {
        XCTAssertNil(CustomTTSEndpoint.validatedBaseURL(""))
        XCTAssertNil(CustomTTSEndpoint.validatedBaseURL("http://example.com/v1"))
        XCTAssertNil(CustomTTSEndpoint.validatedBaseURL("not a url"))
        XCTAssertNil(CustomTTSEndpoint.validatedBaseURL("https://"))
        XCTAssertNil(CustomTTSEndpoint.validatedBaseURL("ftp://example.com"))
    }

    func testSpeechURLPreservesPathPrefix() {
        let base = CustomTTSEndpoint.validatedBaseURL("https://example.com/openai/v1")!
        XCTAssertEqual(
            CustomTTSEndpoint.speechURL(base: base).absoluteString,
            "https://example.com/openai/v1/audio/speech"
        )
    }

    func testSpeechURLToleratesTrailingSlash() {
        let base = CustomTTSEndpoint.validatedBaseURL("https://example.com/openai/v1/")!
        XCTAssertEqual(
            CustomTTSEndpoint.speechURL(base: base).absoluteString,
            "https://example.com/openai/v1/audio/speech"
        )
    }

    func testSpeechURLWithBareHost() {
        let base = CustomTTSEndpoint.validatedBaseURL("https://example.com")!
        XCTAssertEqual(
            CustomTTSEndpoint.speechURL(base: base).absoluteString,
            "https://example.com/audio/speech"
        )
    }

    // MARK: - Failure classification

    private let billingBody = Data(
        #"{"error":{"message":"Account inactive","type":"billing","code":"billing_not_active"}}"#.utf8
    )

    func testAuthFailureWithOldKeySuggestsExpiry() {
        let saved = Date(timeIntervalSinceNow: -29 * 24 * 60 * 60)
        let message = CustomEndpointFailure.describe(
            status: 401, data: Data(), keySavedAt: saved
        )
        XCTAssertTrue(message.contains("may have expired"), message)
    }

    func testAuthFailureAtExactly28DaysSuggestsExpiry() {
        let now = Date()
        let saved = now.addingTimeInterval(-CustomEndpointFailure.keyExpiryHint)
        let message = CustomEndpointFailure.describe(
            status: 403, data: Data(), keySavedAt: saved, now: now
        )
        XCTAssertTrue(message.contains("may have expired"), message)
    }

    func testAuthFailureJustUnder28DaysReportsRejection() {
        let now = Date()
        let saved = now.addingTimeInterval(-CustomEndpointFailure.keyExpiryHint + 60)
        let message = CustomEndpointFailure.describe(
            status: 401, data: Data(), keySavedAt: saved, now: now
        )
        XCTAssertTrue(message.contains("rejected"), message)
        XCTAssertTrue(message.contains("401"), message)
    }

    func testAuthFailureWithFreshKeyReportsRejection() {
        let message = CustomEndpointFailure.describe(
            status: 403, data: Data(), keySavedAt: Date()
        )
        XCTAssertTrue(message.contains("rejected"), message)
    }

    func testAuthFailureWithUnknownSaveDateReportsRejection() {
        let message = CustomEndpointFailure.describe(
            status: 401, data: Data(), keySavedAt: nil
        )
        XCTAssertTrue(message.contains("rejected"), message)
    }

    func testNonAuthFailurePassesThroughErrorBody() {
        let message = CustomEndpointFailure.describe(
            status: 429, data: billingBody, keySavedAt: nil
        )
        XCTAssertTrue(message.contains("Account inactive"), message)
    }

    func testConnectionFailureCodesAreClassified() {
        let connectionCodes: [URLError.Code] = [
            .cannotConnectToHost, .timedOut, .notConnectedToInternet,
            .cannotFindHost, .networkConnectionLost, .dnsLookupFailed
        ]
        for code in connectionCodes {
            XCTAssertTrue(
                CustomEndpointFailure.isConnectionFailure(URLError(code)),
                "\(code) should read as a connection failure"
            )
        }
        XCTAssertFalse(CustomEndpointFailure.isConnectionFailure(URLError(.badServerResponse)))
        XCTAssertFalse(CustomEndpointFailure.isConnectionFailure(URLError(.cancelled)))
    }

    // MARK: - Request body parity with the OpenAI client

    func testRequestBodyMatchesOpenAIWireFormat() throws {
        let body = try OpenAITTSClient.requestBody(
            text: "hello", voiceID: "alloy", modelID: "tts-1", speed: 1.0
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "tts-1")
        XCTAssertEqual(json["input"] as? String, "hello")
        XCTAssertEqual(json["voice"] as? String, "alloy")
        XCTAssertEqual(json["response_format"] as? String, "mp3")
        XCTAssertEqual(json["speed"] as? Double, 1.0)
    }

    func testRequestBodyClampsSpeed() throws {
        let body = try OpenAITTSClient.requestBody(
            text: "x", voiceID: "alloy", modelID: "tts-1", speed: 9.0
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["speed"] as? Double, 4.0)
    }

    // MARK: - Preferences

    func testCustomTTSPreferencesDefaultAndRoundTrip() {
        XCTAssertEqual(Preferences.customTTSVoiceID(from: defaults), "alloy")
        XCTAssertEqual(Preferences.customTTSModelID(from: defaults), "tts-1")
        XCTAssertEqual(Preferences.customTTSBaseURLString(from: defaults), "")
        XCTAssertNil(Preferences.customTTSKeySavedAt(from: defaults))

        Preferences.setCustomTTSVoiceID("marin", to: defaults)
        Preferences.setCustomTTSModelID("gpt-4o-mini-tts", to: defaults)
        Preferences.setCustomTTSBaseURLString("https://example.com/v1", to: defaults)
        let stamp = Date(timeIntervalSince1970: 1_755_000_000)
        Preferences.setCustomTTSKeySavedAt(stamp, to: defaults)

        XCTAssertEqual(Preferences.customTTSVoiceID(from: defaults), "marin")
        XCTAssertEqual(Preferences.customTTSModelID(from: defaults), "gpt-4o-mini-tts")
        XCTAssertEqual(Preferences.customTTSBaseURLString(from: defaults), "https://example.com/v1")
        XCTAssertEqual(Preferences.customTTSKeySavedAt(from: defaults), stamp)

        Preferences.setCustomTTSKeySavedAt(nil, to: defaults)
        XCTAssertNil(Preferences.customTTSKeySavedAt(from: defaults))
    }

    func testEmptyCustomVoiceAndModelFallBackToDefaults() {
        Preferences.setCustomTTSVoiceID("", to: defaults)
        Preferences.setCustomTTSModelID("", to: defaults)
        XCTAssertEqual(Preferences.customTTSVoiceID(from: defaults), "alloy")
        XCTAssertEqual(Preferences.customTTSModelID(from: defaults), "tts-1")
    }

    // MARK: - Provider choice

    func testCustomProviderCopyAndLocality() {
        for provider in ReaderSpeechProviderChoice.allCases {
            XCTAssertFalse(provider.title.isEmpty)
            XCTAssertFalse(provider.detail.isEmpty)
            XCTAssertFalse(provider.symbolName.isEmpty)
        }
        XCTAssertFalse(ReaderSpeechProviderChoice.customOpenAICompatible.isLocal)
        XCTAssertEqual(
            Preferences.readerSpeechProvider(from: defaults),
            .appleOnDevice
        )
        Preferences.setReaderSpeechProvider(.customOpenAICompatible, to: defaults)
        XCTAssertEqual(
            Preferences.readerSpeechProvider(from: defaults),
            .customOpenAICompatible
        )
    }
}
