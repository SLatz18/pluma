import AVFoundation
import XCTest
@testable import Pluma

final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreSafeWhenValuesAreMissing() {
        XCTAssertEqual(Preferences.provider(from: defaults), .appleIntelligence)
        XCTAssertEqual(Preferences.intent(from: defaults), .improve)
        XCTAssertEqual(Preferences.ollamaModel(from: defaults), "")
    }

    func testInvalidRawValuesFallBackToDefaults() {
        defaults.set("unknown-provider", forKey: Preferences.providerKey)
        defaults.set("unknown-intent", forKey: Preferences.intentKey)

        XCTAssertEqual(Preferences.provider(from: defaults), .appleIntelligence)
        XCTAssertEqual(Preferences.intent(from: defaults), .improve)
    }

    func testStoredValuesRoundTrip() {
        defaults.set(RewriteProviderChoice.ollama.rawValue, forKey: Preferences.providerKey)
        defaults.set(RewriteIntent.professional.rawValue, forKey: Preferences.intentKey)
        defaults.set("qwen3:8b", forKey: Preferences.ollamaModelKey)

        XCTAssertEqual(Preferences.provider(from: defaults), .ollama)
        XCTAssertEqual(Preferences.intent(from: defaults), .professional)
        XCTAssertEqual(Preferences.ollamaModel(from: defaults), "qwen3:8b")
    }

    func testDictationMicDefaultsToSystemAndRoundTrips() {
        XCTAssertEqual(Preferences.dictationMicUID(from: defaults), "")
        XCTAssertEqual(Preferences.dictationMicName(from: defaults), "")

        Preferences.setDictationMic(uid: "BuiltInMicUID", name: "MacBook Pro Microphone", to: defaults)
        XCTAssertEqual(Preferences.dictationMicUID(from: defaults), "BuiltInMicUID")
        XCTAssertEqual(Preferences.dictationMicName(from: defaults), "MacBook Pro Microphone")

        // Selecting the system default clears the pin and its display name.
        Preferences.setDictationMic(uid: "", name: "", to: defaults)
        XCTAssertEqual(Preferences.dictationMicUID(from: defaults), "")
        XCTAssertEqual(Preferences.dictationMicName(from: defaults), "")
    }

    func testMissingPinnedMicFallsBackToSystemDefault() {
        Preferences.setDictationMic(uid: "no-such-device-uid", name: "Ghost Mic", to: defaults)
        XCTAssertFalse(MicrophoneSelection.isPinnedMicrophoneAvailable(from: defaults))
        // Capture must not fail hard on a missing pin: it resolves to the
        // system default device (or nil only when the Mac has no input at all).
        let resolved = MicrophoneSelection.captureDevice(from: defaults)
        XCTAssertEqual(resolved?.uniqueID, AVCaptureDevice.default(for: .audio)?.uniqueID)
    }
}
