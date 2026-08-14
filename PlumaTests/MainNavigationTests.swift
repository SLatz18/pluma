import XCTest
@testable import Pluma

@MainActor
final class MainNavigationTests: XCTestCase {
    func testAIToFeatureRouteReturnsToExactAISection() {
        let navigation = MainNavigation()

        navigation.navigate(
            to: .dictation,
            focus: .dictationEngines,
            returningTo: .ai,
            returnFocus: .aiDictation
        )

        XCTAssertEqual(navigation.page, .dictation)
        XCTAssertEqual(navigation.focus, .dictationEngines)
        XCTAssertTrue(navigation.canReturn(from: .dictation))

        navigation.goBack(from: .dictation)

        XCTAssertEqual(navigation.page, .ai)
        XCTAssertEqual(navigation.focus, .aiDictation)
        XCTAssertFalse(navigation.canReturn(from: .dictation))
    }

    func testDirectSidebarSelectionClearsContextualRoute() {
        let navigation = MainNavigation()
        navigation.navigate(
            to: .reader,
            focus: .readerSpeech,
            returningTo: .ai,
            returnFocus: .aiReader
        )

        navigation.select(.privacy)

        XCTAssertEqual(navigation.page, .privacy)
        XCTAssertNil(navigation.focus)
        XCTAssertFalse(navigation.canReturn(from: .reader))
    }
}
