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
}
