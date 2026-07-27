import XCTest
@testable import Rewrite

final class WordDifferTests: XCTestCase {
    func testIdenticalTextProducesOnlyUnchangedSegments() {
        let segments = WordDiffer.diff(original: "hello world", revised: "hello world")
        XCTAssertTrue(segments.allSatisfy { $0.kind == .unchanged })
        XCTAssertEqual(WordDiffer.changeCount(segments), 0)
    }

    func testSingleWordReplacement() {
        let segments = WordDiffer.diff(original: "hello world", revised: "hello there")

        XCTAssertEqual(segments.map(\.kind), [.unchanged, .removed, .added])
        XCTAssertEqual(segments.map(\.text), ["hello", "world", "there"])
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testInsertionCountsAsOneChange() {
        let segments = WordDiffer.diff(original: "hello", revised: "hello world")

        XCTAssertEqual(segments.map(\.kind), [.unchanged, .added])
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testDeletionCountsAsOneChange() {
        let segments = WordDiffer.diff(original: "hello world", revised: "hello")

        XCTAssertEqual(segments.map(\.kind), [.unchanged, .removed])
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testAdjacentReplacementCountsOnce() {
        let segments = WordDiffer.diff(original: "the quick fox", revised: "a fast fox")

        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }
}
