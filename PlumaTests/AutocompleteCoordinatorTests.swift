import XCTest
@testable import Pluma

final class AutocompleteCoordinatorTests: XCTestCase {
    func testStandaloneSingleLetterWordAcceptsAAndI() {
        XCTAssertTrue(AutocompleteCoordinator.isStandaloneSingleLetterWord("a"))
        XCTAssertTrue(AutocompleteCoordinator.isStandaloneSingleLetterWord("A"))
        XCTAssertTrue(AutocompleteCoordinator.isStandaloneSingleLetterWord("i"))
        XCTAssertTrue(AutocompleteCoordinator.isStandaloneSingleLetterWord("I"))
    }

    func testStandaloneSingleLetterWordRejectsOtherLetters() {
        let notWords: [Character] = ["y", "b", "n", "z", "x", "Y", "B"]
        for letter in notWords {
            XCTAssertFalse(
                AutocompleteCoordinator.isStandaloneSingleLetterWord(letter),
                "expected '\(letter)' to not be treated as a standalone word"
            )
        }
    }
}
