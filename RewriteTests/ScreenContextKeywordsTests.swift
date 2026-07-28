import XCTest
@testable import Rewrite

final class ScreenContextKeywordsTests: XCTestCase {
    func testKeepsProperNounsAndProductNames() {
        let terms = ScreenContextProvider.contextualStrings(
            from: "Hi Priya, can you review the SpeechAnalyzer rollout for Northwind?"
        )

        XCTAssertTrue(terms.contains("Priya"))
        XCTAssertTrue(terms.contains("SpeechAnalyzer"))
        XCTAssertTrue(terms.contains("Northwind"))
    }

    func testDropsOrdinaryWordsAndSentenceOpeners() {
        let terms = ScreenContextProvider.contextualStrings(
            from: "The quick brown fox. Thanks! Please reply when you can."
        )

        XCTAssertFalse(terms.contains("The"))
        XCTAssertFalse(terms.contains("Thanks"))
        XCTAssertFalse(terms.contains("Please"))
        XCTAssertFalse(terms.contains("quick"))
    }

    func testStripsPunctuationAndDeduplicates() {
        let terms = ScreenContextProvider.contextualStrings(
            from: "Kubernetes, Kubernetes; (Kubernetes) — Kubernetes"
        )

        XCTAssertEqual(terms, ["Kubernetes"])
    }

    func testKeepsIdentifiersContainingDigits() {
        let terms = ScreenContextProvider.contextualStrings(from: "ticket TKT1234567 and REF-2468")

        XCTAssertTrue(terms.contains("TKT1234567"))
        XCTAssertTrue(terms.contains("REF-2468"))
    }

    func testIgnoresShortTokens() {
        let terms = ScreenContextProvider.contextualStrings(from: "AB X Qq ZZZ")

        XCTAssertFalse(terms.contains("AB"))
        XCTAssertFalse(terms.contains("X"))
        XCTAssertTrue(terms.contains("ZZZ"))
    }

    func testCapsTheNumberOfTerms() {
        let text = (1...200).map { "Term\($0)" }.joined(separator: " ")
        let terms = ScreenContextProvider.contextualStrings(from: text)

        XCTAssertLessThanOrEqual(terms.count, 60)
        XCTAssertFalse(terms.isEmpty)
    }
}
