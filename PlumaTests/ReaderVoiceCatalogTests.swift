import XCTest
@testable import Pluma

final class ReaderVoiceCatalogTests: XCTestCase {
    func testOpenAISpeedMapsMidRateNearOne() {
        let mid = Preferences.defaultReaderRate
        let speed = ReaderVoiceCatalog.openAISpeed(fromReaderRate: mid)
        XCTAssertEqual(speed, 1.0, accuracy: 0.05)
    }

    func testOpenAISpeedClampsToListeningBand() {
        let slow = ReaderVoiceCatalog.openAISpeed(fromReaderRate: 0.0)
        let fast = ReaderVoiceCatalog.openAISpeed(fromReaderRate: 1.0)
        XCTAssertEqual(slow, 0.657, accuracy: 0.01)
        XCTAssertEqual(fast, 1.257, accuracy: 0.01)
    }

    func testPreferredIdentifierPrefersPremiumThenEnhanced() {
        XCTAssertEqual(
            ReaderVoiceCatalog.preferredIdentifier(in: []),
            ""
        )
    }

    func testSpeechProviderDefaultsLocal() {
        XCTAssertEqual(ReaderSpeechProviderChoice.defaultProvider, .appleOnDevice)
        XCTAssertTrue(ReaderSpeechProviderChoice.appleOnDevice.isLocal)
        XCTAssertFalse(ReaderSpeechProviderChoice.openAI.isLocal)
    }
}

final class OpenAITTSClientTests: XCTestCase {
    func testRequestBodyIncludesModelVoiceAndClampedSpeed() throws {
        let data = try OpenAITTSClient.requestBody(
            text: "Hello there",
            voice: .nova,
            model: .tts1HD,
            speed: 9.0
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "tts-1-hd")
        XCTAssertEqual(json["voice"] as? String, "nova")
        XCTAssertEqual(json["input"] as? String, "Hello there")
        XCTAssertEqual(json["response_format"] as? String, "mp3")
        XCTAssertEqual(json["speed"] as? Double, 4.0)
    }

    func testRequestBodyClampsSlowSpeed() throws {
        let data = try OpenAITTSClient.requestBody(
            text: "Slow",
            voice: .alloy,
            model: .tts1,
            speed: 0.01
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["speed"] as? Double, 0.25)
    }
}
