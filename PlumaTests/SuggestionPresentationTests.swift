import XCTest
@testable import Pluma

// The choice between drawing suggestions into the writer's line and showing them
// on a chip below it. The default matters: inline needs geometry only some apps
// report, and getting it wrong is visible on every keystroke.
final class SuggestionPresentationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "pluma.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // A fresh install gets the chip, because it is the one that works everywhere.
    func testChipIsTheDefault() {
        XCTAssertFalse(Preferences.inlineSuggestions(from: defaults))
    }

    func testInlineCanBeTurnedOnAndOff() {
        Preferences.setInlineSuggestions(true, to: defaults)
        XCTAssertTrue(Preferences.inlineSuggestions(from: defaults))

        Preferences.setInlineSuggestions(false, to: defaults)
        XCTAssertFalse(Preferences.inlineSuggestions(from: defaults))
    }

    // The chip covers nothing the writer has already put down, so unlike ghost
    // text it has no reason to refuse a caret in the middle of a line. This is
    // the eligibility ghost text still answers no to.
    func testGhostTextStillRefusesMidLineCarets() {
        let precise = CaretGeometry(
            rect: CGRect(x: 40, y: 100, width: 1, height: 17), source: .exactCaret
        )
        let midLine = GhostTextEligibility.of(text: "hello there", caretLocation: 5)
        XCTAssertFalse(midLine.allows(precise))
    }
}
