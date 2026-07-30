import XCTest
@testable import Pluma

final class CompletionSuggestionTests: XCTestCase {
    func testRawOutputIsTrimmedToSingleLine() {
        let suggestion = CompletionSuggestion(rawOutput: "first line\nsecond line  ")
        XCTAssertEqual(suggestion.remaining, "first line")
    }

    func testLeadingSpaceMarksWordBoundary() {
        var suggestion = CompletionSuggestion(rawOutput: " results were achieved")
        XCTAssertEqual(suggestion.remaining, " results were achieved")
        XCTAssertEqual(suggestion.acceptNextWord(), " results ")
        XCTAssertEqual(suggestion.remaining, "were achieved")
    }

    func testConsumeTypedTextMatchesAcrossLeadingSpace() {
        var suggestion = CompletionSuggestion(rawOutput: " results were")
        XCTAssertTrue(suggestion.consumeTypedText("results"))
        XCTAssertEqual(suggestion.remaining, " were")
    }

    func testWhitespaceOnlyOutputIsEmpty() {
        XCTAssertTrue(CompletionSuggestion(rawOutput: "   ").isEmpty)
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

    // MARK: Scope

    // Partway through a word, the only thing worth offering is the rest of that
    // word — where the sentence goes next is a separate guess.
    func testMidWordScopeKeepsOnlyTheWord() {
        let suggestion = CompletionSuggestion(
            rawOutput: "tion of the quarterly report is due",
            context: "We should finish the execu",
            scope: .word
        )
        XCTAssertEqual(suggestion.remaining, "tion")
    }

    // Thin context cannot support a clause, so a few words at most.
    func testBriefScopeCapsAtAFewWords() {
        let suggestion = CompletionSuggestion(
            rawOutput: " to the meeting room on the second floor tomorrow",
            context: "Please come",
            scope: .brief
        )
        XCTAssertEqual(suggestion.remaining, " to the meeting room")
    }

    // The leading space is a boundary marker, not a word: a one-word limit that
    // counted it would leave nothing at all.
    func testWordLimitPreservesTheLeadingSpace() {
        let suggestion = CompletionSuggestion(
            rawOutput: " tomorrow morning at nine",
            context: "Let us meet",
            scope: .word
        )
        XCTAssertEqual(suggestion.remaining, " tomorrow")
    }

    func testMidWordContextChoosesWordScope() {
        XCTAssertEqual(
            CompletionSuggestion.scope(forContext: "the execu", endsMidWord: true), .word
        )
    }

    func testShortContextChoosesBriefScope() {
        XCTAssertEqual(
            CompletionSuggestion.scope(forContext: "Please come", endsMidWord: false), .brief
        )
    }

    func testAmpleContextChoosesPhraseScope() {
        let ample = "The deployment failed again this morning so I spent an hour digging"
        XCTAssertEqual(
            CompletionSuggestion.scope(forContext: ample, endsMidWord: false), .phrase
        )
    }

    // Mid-word wins over context length: a long paragraph that stops halfway
    // through a word still only wants that word finished.
    func testMidWordBeatsAmpleContext() {
        let ample = "The deployment failed again this morning so I spent an hour investiga"
        XCTAssertEqual(
            CompletionSuggestion.scope(forContext: ample, endsMidWord: true), .word
        )
    }

    // MARK: Mid-word completion

    private let documenta = ["documentation", "documentary", "documentaries"]

    // The model's answer is kept when it really does finish the word.
    func testModelWordCompletionIsUsedWhenItExtendsThePartial() {
        let completion = CompletionSuggestion.wordCompletion(
            forPartial: "execu",
            modelSuggestion: "tion of the report",
            candidates: ["executive", "execution", "executives"]
        )
        XCTAssertEqual(completion, "tion")
    }

    // The failure seen live: asked to continue "documenta" the model answered
    // "documents.", which appended would read "documentadocuments."
    func testModelAnswerThatWouldCorruptTheWordIsReplaced() {
        let completion = CompletionSuggestion.wordCompletion(
            forPartial: "documenta", modelSuggestion: "documents.", candidates: documenta
        )
        XCTAssertEqual(completion, "tion")
    }

    func testFallsBackToTheSpellCheckerWhenTheModelSaysNothingUseful() {
        let completion = CompletionSuggestion.wordCompletion(
            forPartial: "documenta", modelSuggestion: "", candidates: documenta
        )
        XCTAssertEqual(completion, "tion")
    }

    func testNoCompletionWhenNothingExtendsThePartial() {
        XCTAssertEqual(
            CompletionSuggestion.wordCompletion(
                forPartial: "qqqq", modelSuggestion: "something", candidates: []
            ),
            ""
        )
    }

    // Candidates that merely equal the partial are not completions.
    func testCandidateEqualToThePartialIsNotACompletion() {
        XCTAssertEqual(
            CompletionSuggestion.wordCompletion(
                forPartial: "hour", modelSuggestion: "", candidates: ["hour"]
            ),
            ""
        )
    }

    func testMatchingIsCaseInsensitive() {
        let completion = CompletionSuggestion.wordCompletion(
            forPartial: "Execu", modelSuggestion: "tion", candidates: ["execution"]
        )
        XCTAssertEqual(completion, "tion")
    }

    func testSuggestionShorterThanTheLimitIsUntouched() {
        let suggestion = CompletionSuggestion(
            rawOutput: " the logs", context: "I spent an hour digging", scope: .brief
        )
        XCTAssertEqual(suggestion.remaining, " the logs")
    }

    // MARK: Prompt leakage

    // Seen live in TextEdit: the model finished the prompt instead of the
    // sentence and offered "</context>" as the completion.
    func testPromptMarkersProduceEmptySuggestion() {
        let leaks = [
            "</context>",
            " </context>",
            "the logs</context>",
            "</surrounding>",
            "</style-profile>",
            "<context>"
        ]
        for leak in leaks {
            XCTAssertTrue(CompletionSuggestion(rawOutput: leak).isEmpty, leak)
        }
    }

    // Ordinary angle brackets in prose are not prompt markup.
    func testAngleBracketsInNormalTextAreKept() {
        XCTAssertFalse(CompletionSuggestion(rawOutput: " if x < y then stop").isEmpty)
        XCTAssertFalse(CompletionSuggestion(rawOutput: " the <b>bold</b> part").isEmpty)
    }

    // MARK: Echoed context

    // The failure seen in TextEdit: the model restates the last word of the
    // line before continuing it.
    func testRepeatedTrailingWordIsStripped() {
        let suggestion = CompletionSuggestion(
            rawOutput: " section is the most engaging part",
            context: "I read it this morning and I think the middle section"
        )
        XCTAssertEqual(suggestion.remaining, " is the most engaging part")
    }

    // The worse failure: the whole line handed straight back. Nothing survives
    // stripping, so there is no suggestion to show.
    func testVerbatimEchoOfTheWholeLineProducesNothing() {
        let line = "I wanted to follow up on the pricing question you raised in the meeting"
        XCTAssertTrue(CompletionSuggestion(rawOutput: line, context: line).isEmpty)
    }

    // The variant that slipped past the first fix: the line is restated and the
    // full stop the writer had not typed yet is added, so the echo no longer
    // ends on whitespace.
    func testEchoThatAddsTrailingPunctuationIsStillCaught() {
        let typed = "I wanted to follow up on the pricing question you raised in the meeting"
        XCTAssertTrue(
            CompletionSuggestion(rawOutput: " \(typed).", context: typed).isEmpty
        )
    }

    // Punctuation mid-echo counts as a word boundary too, and what survives
    // attaches tight to the writer's last word rather than gaining a space.
    func testEchoEndingAtPunctuationIsStripped() {
        let suggestion = CompletionSuggestion(
            rawOutput: "the meeting. Let me know",
            context: "I raised it in the meeting"
        )
        XCTAssertEqual(suggestion.remaining, ". Let me know")
    }

    // MARK: Echoes seen in a real session
    //
    // Every case below was logged while typing one sentence into TextEdit, and
    // every one of them reached the screen.

    // The caret sits after a space. That trailing space made each candidate one
    // character longer than the echo it was meant to match, so nothing matched.
    func testEchoIsCaughtWhenTheCaretFollowsASpace() {
        XCTAssertTrue(
            CompletionSuggestion(
                rawOutput: "test of the", context: "this is a test of the "
            ).isEmpty
        )
    }

    func testEchoOfTheWholeLineIsCaughtAfterASpace() {
        XCTAssertTrue(
            CompletionSuggestion(
                rawOutput: "this is a test of the functionality from I",
                context: "this is a test of the functionality from "
            ).isEmpty
        )
    }

    // The model restated words it had not finished: "of the functionali" against
    // a context already holding "of the functionality". Redundant either way.
    func testUnfinishedRestatementIsCaught() {
        XCTAssertTrue(
            CompletionSuggestion(
                rawOutput: "of the functionali",
                context: "this is a test of the functionality"
            ).isEmpty
        )
    }

    func testRestatementBeginningMidContextIsCaught() {
        XCTAssertTrue(
            CompletionSuggestion(
                rawOutput: "tionality of the functionality",
                context: "f the functionality of the functionality"
            ).isEmpty
        )
    }

    // Logged live: the model restated three words and finished the last one, so
    // accepting it wrote "what I am work I am working on."
    func testRestatementThatFinishesTheLastWordIsStripped() {
        let suggestion = CompletionSuggestion(
            rawOutput: "I am working on.",
            context: "trying to figure out what I am work"
        )
        XCTAssertEqual(suggestion.remaining, "ing on.")
    }

    // One shared word is not evidence of anything, so a longer word that merely
    // starts the same survives intact.
    func testSingleSharedWordDoesNotLicenseAMidWordCut() {
        let suggestion = CompletionSuggestion(
            rawOutput: "applesauce is better", context: "I ate an apple"
        )
        XCTAssertEqual(suggestion.remaining, "applesauce is better")
    }

    // The guard must not swallow real continuations that happen to reuse a word.
    func testContinuationSharingAWordWithTheContextSurvives() {
        let suggestion = CompletionSuggestion(
            rawOutput: " of the new release",
            context: "I read the functionality notes and the scope"
        )
        XCTAssertEqual(suggestion.remaining, " of the new release")
    }

    func testMultipleRepeatedWordsAreStripped() {
        let suggestion = CompletionSuggestion(
            rawOutput: "the middle section needs work",
            context: "I think the middle section"
        )
        XCTAssertEqual(suggestion.remaining, " needs work")
    }

    func testEchoMatchIsCaseInsensitive() {
        let suggestion = CompletionSuggestion(
            rawOutput: "Section is fine",
            context: "I think the middle section"
        )
        XCTAssertEqual(suggestion.remaining, " is fine")
    }

    // A genuine continuation must survive untouched, including the leading
    // space that marks the word boundary.
    func testGenuineContinuationIsUntouched() {
        let suggestion = CompletionSuggestion(
            rawOutput: " the logs to figure out what went wrong",
            context: "I spent an hour digging through"
        )
        XCTAssertEqual(suggestion.remaining, " the logs to figure out what went wrong")
    }

    // Only whole words count as an echo. "mid" is a prefix of "midpoint", but
    // cutting it would leave the writer with "the midpoint" spelled "the point".
    func testPartialWordOverlapIsNotTreatedAsAnEcho() {
        let suggestion = CompletionSuggestion(
            rawOutput: "midpoint of the range",
            context: "the value sits near the mid"
        )
        XCTAssertEqual(suggestion.remaining, "midpoint of the range")
    }

    // A mid-word continuation has no leading space and must not gain one, or
    // insertion breaks the word it was completing.
    func testMidWordContinuationKeepsNoLeadingSpace() {
        let suggestion = CompletionSuggestion(
            rawOutput: "point of the range",
            context: "the value sits near the mid"
        )
        XCTAssertEqual(suggestion.remaining, "point of the range")
    }

    func testSingleRepeatedLetterIsLeftAlone() {
        let suggestion = CompletionSuggestion(
            rawOutput: "A is the cheaper option",
            context: "between the two I would pick A"
        )
        XCTAssertEqual(suggestion.remaining, "A is the cheaper option")
    }

    func testEmptyContextLeavesTheSuggestionAlone() {
        let suggestion = CompletionSuggestion(rawOutput: " and then some", context: "")
        XCTAssertEqual(suggestion.remaining, " and then some")
    }

    func testCompletionPromptDelimitsContext() {
        let prompt = PromptComposer.completionUserPrompt(context: "Some context")
        XCTAssertTrue(prompt.contains("<context>\nSome context\n</context>"))
        XCTAssertTrue(prompt.contains("Return only the continuation text."))
    }

    func testCompletionPromptIncludesSurroundingWhenProvided() {
        let withSurrounding = PromptComposer.completionUserPrompt(
            context: "replying now",
            surrounding: "Email from Dana about the Q3 report"
        )
        XCTAssertTrue(withSurrounding.contains("<surrounding>\nEmail from Dana about the Q3 report\n</surrounding>"))

        let without = PromptComposer.completionUserPrompt(context: "replying now")
        XCTAssertFalse(without.contains("<surrounding>"))
    }
}
