import XCTest
@testable import Pluma

final class WordDifferTests: XCTestCase {
    func testIdenticalTextProducesNoChanges() {
        let segments = WordDiffer.diff(original: "hello world", revised: "hello world")

        XCTAssertTrue(segments.allSatisfy { $0.kind == .unchanged })
        XCTAssertEqual(WordDiffer.changeCount(segments), 0)
    }

    func testSingleWordReplacementCountsAsOneChange() {
        let segments = WordDiffer.diff(original: "hello world", revised: "hello there")

        XCTAssertEqual(segments.map(\.kind), [.unchanged, .removed, .added])
        XCTAssertEqual(segments.map(\.text), ["hello", "world", "there"])
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testAdjacentReplacementCountsAsOneChange() {
        let segments = WordDiffer.diff(original: "the quick fox", revised: "a fast fox")

        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testEmptyInputsAreHandled() {
        XCTAssertEqual(WordDiffer.diff(original: "", revised: ""), [])
        XCTAssertEqual(
            WordDiffer.diff(original: "", revised: "hello"),
            [DiffSegment(kind: .added, text: "hello")]
        )
    }

    func testLargeInputUsesBoundedCoarseDiff() {
        let original = Array(repeating: "before", count: 501).joined(separator: " ")
        let revised = Array(repeating: "after", count: 501).joined(separator: " ")
        let segments = WordDiffer.diff(original: original, revised: revised)

        XCTAssertEqual(segments.count, 1_002)
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }
}
