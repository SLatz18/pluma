import XCTest
@testable import Rewrite

final class WordDifferTests: XCTestCase {
    func testSubstitutionProducesOneChangeRun() {
        let segments = WordDiffer.diff(
            original: "Hello world",
            revised: "Hello there"
        )

        XCTAssertEqual(
            segments,
            [
                DiffSegment(kind: .unchanged, text: "Hello "),
                DiffSegment(kind: .removed, text: "world"),
                DiffSegment(kind: .added, text: "there")
            ]
        )
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testSeparatedEditsProduceSeparateChangeRuns() {
        let segments = WordDiffer.diff(
            original: "one two three four",
            revised: "one second three fourth"
        )

        XCTAssertEqual(WordDiffer.changeCount(segments), 2)
    }

    func testEmptyOriginalProducesAdditions() {
        let segments = WordDiffer.diff(original: "", revised: "new words")

        XCTAssertEqual(
            segments,
            [
                DiffSegment(kind: .added, text: "new "),
                DiffSegment(kind: .added, text: "words")
            ]
        )
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testIdenticalTextHasNoChanges() {
        let segments = WordDiffer.diff(original: "No changes", revised: "No changes")

        XCTAssertEqual(WordDiffer.changeCount(segments), 0)
    }

    func testWhitespaceOnlyEditIsCounted() {
        let segments = WordDiffer.diff(original: "one\ntwo", revised: "one two")

        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testLargeInputsUseBoundedFallback() {
        let original = Array(repeating: "original", count: 400).joined(separator: " ")
        let revised = Array(repeating: "revised", count: 400).joined(separator: " ")

        let segments = WordDiffer.diff(original: original, revised: revised)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }
}
