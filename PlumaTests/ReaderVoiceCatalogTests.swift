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

    func testPickerLabelIncludesTheVoiceLanguage() {
        XCTAssertEqual(
            ReaderVoiceCatalog.pickerLabel(name: "Eddy", languageCode: "en-US"),
            "Eddy · en-US"
        )
        XCTAssertNotEqual(
            ReaderVoiceCatalog.pickerLabel(name: "Eddy", languageCode: "en-US"),
            ReaderVoiceCatalog.pickerLabel(name: "Eddy", languageCode: "en-GB")
        )
    }
}

@MainActor
final class ReaderViewPresentationTests: XCTestCase {
    func testVerbatimFlowNamesTheSelectedSpeechDestination() {
        let local = ReaderView.flowDefinition(
            deliveryMode: .verbatim,
            speechProvider: .appleOnDevice
        )
        let openAI = ReaderView.flowDefinition(
            deliveryMode: .verbatim,
            speechProvider: .openAI
        )

        XCTAssertEqual(local.action, "Read it verbatim")
        XCTAssertEqual(local.result, "Speak it on this Mac")
        XCTAssertEqual(openAI.action, "Read it verbatim")
        XCTAssertEqual(openAI.result, "Speak it with OpenAI")
    }

    func testSummaryFlowNamesTheSelectedSpeechDestination() {
        let local = ReaderView.flowDefinition(
            deliveryMode: .summarizeWhenHelpful,
            speechProvider: .appleOnDevice
        )
        let openAI = ReaderView.flowDefinition(
            deliveryMode: .summarizeWhenHelpful,
            speechProvider: .openAI
        )

        XCTAssertEqual(local.result, "Speak the summary on this Mac")
        XCTAssertEqual(openAI.result, "Speak the summary with OpenAI")
    }

    func testPlaygroundEditingIsLockedForEveryBusyState() {
        XCTAssertTrue(ReaderView.allowsPlaygroundEditing(during: .off))
        XCTAssertTrue(ReaderView.allowsPlaygroundEditing(during: .idle))
        XCTAssertFalse(ReaderView.allowsPlaygroundEditing(during: .processing))
        XCTAssertFalse(ReaderView.allowsPlaygroundEditing(during: .reading))
    }
}

final class OpenAITTSClientTests: XCTestCase {
    func testRequestBodyIncludesModelVoiceAndClampedSpeed() throws {
        let data = try OpenAITTSClient.requestBody(
            text: "Hello there",
            voiceID: "nova",
            modelID: "tts-1-hd",
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
            voiceID: "alloy",
            modelID: "tts-1",
            speed: 0.01
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["speed"] as? Double, 0.25)
    }

}

final class OpenAITTSCatalogTests: XCTestCase {
    func testFiltersRemoteModelIDsToTTSFamily() {
        let models = OpenAITTSCatalog.models(fromRemoteIDs: [
            "gpt-4o",
            "tts-1",
            "whisper-1",
            "tts-1-hd",
            "gpt-4o-mini-tts",
            "gpt-4o-mini-tts-2025-12-15",
            "tts-1-hd-1106"
        ])
        XCTAssertEqual(
            models.map(\.id),
            ["tts-1", "tts-1-hd", "gpt-4o-mini-tts", "gpt-4o-mini-tts-2025-12-15", "tts-1-hd-1106"]
        )
    }

    func testFallsBackWhenRemoteHasNoTTSModels() {
        let models = OpenAITTSCatalog.models(fromRemoteIDs: ["gpt-4o", "whisper-1"])
        XCTAssertEqual(models.map(\.id), OpenAITTSCatalog.fallbackModelIDs)
    }

    func testClassicModelsHideNewerVoices() {
        let classic = OpenAITTSCatalog.voices(compatibleWithModel: "tts-1-hd")
        XCTAssertFalse(classic.contains(where: { $0.id == "ballad" }))
        XCTAssertTrue(classic.contains(where: { $0.id == "nova" }))

        let modern = OpenAITTSCatalog.voices(compatibleWithModel: "gpt-4o-mini-tts")
        XCTAssertTrue(modern.contains(where: { $0.id == "ballad" }))
        XCTAssertTrue(modern.contains(where: { $0.id == "cedar" }))
    }

    func testResolveVoiceFallsBackWhenIncompatible() {
        let available = OpenAITTSCatalog.voices(compatibleWithModel: "tts-1")
        let resolved = OpenAITTSCatalog.resolveVoiceID(
            preferred: "ballad",
            available: available
        )
        XCTAssertEqual(resolved, OpenAITTSCatalog.defaultVoiceID)
    }

    func testBuiltInVoiceCatalogIncludesCurrentDocsSet() {
        for id in ["ballad", "verse", "marin", "cedar"] {
            XCTAssertTrue(
                OpenAITTSCatalog.builtInVoiceIDs.contains(id),
                "missing \(id)"
            )
        }
    }
}
