import XCTest
@testable import Rewrite

final class CompletionSuggestionTests: XCTestCase {
    func testRawOutputIsTrimmedToSingleLine() {
        let suggestion = CompletionSuggestion(rawOutput: "  first line\nsecond line  ")
        XCTAssertEqual(suggestion.remaining, "first line")
    }

    func testRawOutputIsCappedAtMaxWords() {
        let manyWords = (1...30).map { "word\($0)" }.joined(separator: " ")
        let suggestion = CompletionSuggestion(rawOutput: manyWords)
        XCTAssertEqual(
            suggestion.remaining,
            (1...CompletionSuggestion.maxWords).map { "word\($0)" }.joined(separator: " ")
        )
    }

    func testTriggerRequiresMinimumContext() {
        XCTAssertFalse(CompletionSuggestion.shouldTrigger(for: "Hi"))
        XCTAssertTrue(
            CompletionSuggestion.shouldTrigger(
                for: "Thanks for sending the draft over yesterday,"
            )
        )
    }

    func testConsumeTypedTextTrimsMatchingPrefix() {
        var suggestion = CompletionSuggestion(rawOutput: "the report by Friday")
        XCTAssertTrue(suggestion.consumeTypedText("the "))
        XCTAssertEqual(suggestion.remaining, "report by Friday")
    }

    func testConsumeTypedTextIsCaseInsensitive() {
        var suggestion = CompletionSuggestion(rawOutput: "The report")
        XCTAssertTrue(suggestion.consumeTypedText("the "))
        XCTAssertEqual(suggestion.remaining, "report")
    }

    func testConsumeTypedTextRejectsMismatch() {
        var suggestion = CompletionSuggestion(rawOutput: "the report")
        XCTAssertFalse(suggestion.consumeTypedText("xyz"))
    }

    func testConsumeTypedTextReturnsFalseWhenExhausted() {
        var suggestion = CompletionSuggestion(rawOutput: "done")
        XCTAssertFalse(suggestion.consumeTypedText("done"))
        XCTAssertTrue(suggestion.isEmpty)
    }

    func testAcceptNextWordTakesWordPlusTrailingSpace() {
        var suggestion = CompletionSuggestion(rawOutput: "review the numbers")
        XCTAssertEqual(suggestion.acceptNextWord(), "review ")
        XCTAssertEqual(suggestion.remaining, "the numbers")
    }

    func testAcceptNextWordOnLastWordEmptiesSuggestion() {
        var suggestion = CompletionSuggestion(rawOutput: "numbers")
        XCTAssertEqual(suggestion.acceptNextWord(), "numbers")
        XCTAssertTrue(suggestion.isEmpty)
    }

    func testAcceptAllReturnsEverything() {
        var suggestion = CompletionSuggestion(rawOutput: "the whole thing")
        XCTAssertEqual(suggestion.acceptAll(), "the whole thing")
        XCTAssertTrue(suggestion.isEmpty)
    }

    func testRefusalPreamblesProduceEmptySuggestion() {
        let refusals = [
            "I'm sorry, but as an LLM created by Apple, I cannot comply",
            "I cannot complete that text.",
            "I can't help with that",
            "As an AI, I must decline"
        ]
        for refusal in refusals {
            XCTAssertTrue(CompletionSuggestion(rawOutput: refusal).isEmpty, refusal)
        }
    }

    func testNormalCompletionsAreNotFlaggedAsRefusals() {
        XCTAssertFalse(CompletionSuggestion(rawOutput: "the report by Friday").isEmpty)
        XCTAssertFalse(CompletionSuggestion.looksLikeRefusal("the report by Friday"))
    }

    func testCompletionPromptDelimitsContext() {
        let prompt = PromptComposer.completionUserPrompt(context: "Some context")
        XCTAssertTrue(prompt.contains("<context>\nSome context\n</context>"))
        XCTAssertTrue(prompt.contains("Return only the continuation text."))
    }
}
