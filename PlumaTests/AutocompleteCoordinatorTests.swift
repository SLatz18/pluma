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

    func testTrailingWordFragmentKeepsContractionsWhole() {
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("it's"), "it's")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("Well don't"), "don't")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("Sure, I'm"), "I'm")
        // The typographic apostrophe macOS smart quotes substitute in.
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("it’s"), "it’s")
    }

    func testTrailingWordFragmentReadsPlainWordsUnchanged() {
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("Can y"), "y")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("the execu"), "execu")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment(""), "")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("end. "), "")
    }

    func testTrailingWordFragmentTrimsBoundaryApostrophes() {
        // An apostrophe before the word is a quotation mark, not part of it.
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("say 'hello"), "hello")
        XCTAssertEqual(AutocompleteCoordinator.trailingWordFragment("say ‘y"), "y")
    }
}
