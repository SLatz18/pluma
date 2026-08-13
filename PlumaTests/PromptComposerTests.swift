import XCTest
@testable import Pluma

final class PromptComposerTests: XCTestCase {
    func testEveryIntentAddsItsDirective() {
        for intent in RewriteIntent.allCases {
            let prompt = PromptComposer.userPrompt(intent: intent, text: "Hello")
            XCTAssertTrue(prompt.contains(intent.directive))
        }
    }

    func testSourceTextIsDelimited() {
        let prompt = PromptComposer.userPrompt(intent: .improve, text: "Original words")

        XCTAssertTrue(prompt.contains("<source>\nOriginal words\n</source>"))
        XCTAssertTrue(prompt.contains("Return only the edited text."))
    }

    func testAppleIntelligenceIsTheDefaultProvider() {
        XCTAssertEqual(RewriteProviderChoice.defaultProvider, .appleIntelligence)
    }

    func testDictationCleanupUsesItsOwnDirective() {
        let prompt = PromptComposer.userPrompt(
            directive: PromptComposer.dictationDirective,
            text: "um so i think we should uh ship it"
        )

        XCTAssertTrue(prompt.contains(PromptComposer.dictationDirective))
        XCTAssertTrue(prompt.contains("<source>\num so i think we should uh ship it\n</source>"))
    }

    // Dictation is content, not instruction: the transcript must never be
    // treated as a request to answer.
    func testDictationDirectiveForbidsRespondingToTheTranscript() {
        XCTAssertTrue(PromptComposer.dictationDirective.contains("Never answer"))
        XCTAssertTrue(PromptComposer.dictationDirective.contains("do not rephrase"))
    }

    // MARK: Completion directive chain

    func testDefaultCompletionChainKeepsLegacyInstructions() {
        XCTAssertEqual(
            PromptComposer.completionInstructions(directives: CompletionDirective.defaultChain),
            PromptComposer.completionSystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.completionInstructions(),
            PromptComposer.completionSystemInstructions
        )
    }

    func testEmptyCompletionChainAlsoKeepsBaseInstructions() {
        XCTAssertEqual(
            PromptComposer.completionInstructions(directives: []),
            PromptComposer.completionSystemInstructions
        )
    }

    func testCustomCompletionChainAppendsDirectivesInOrder() {
        let chain: [CompletionDirective] = [.shortCompletions, .avoidCliches]
        let instructions = PromptComposer.completionInstructions(directives: chain)

        XCTAssertTrue(instructions.hasPrefix(PromptComposer.completionSystemInstructions))
        XCTAssertTrue(instructions.contains("1. \(CompletionDirective.shortCompletions.promptDirective)"))
        XCTAssertTrue(instructions.contains("2. \(CompletionDirective.avoidCliches.promptDirective)"))

        let reversed = PromptComposer.completionInstructions(
            directives: [.avoidCliches, .shortCompletions]
        )
        XCTAssertNotEqual(instructions, reversed, "order must change the prompt")
    }

    func testCompletionChainComposesWithStyleProfile() {
        let instructions = PromptComposer.completionInstructions(
            styleProfile: "Short sentences.",
            directives: [.fullSentences]
        )

        XCTAssertTrue(instructions.contains(CompletionDirective.fullSentences.promptDirective))
        XCTAssertTrue(instructions.contains("<style-profile>\nShort sentences.\n</style-profile>"))
    }

    // MARK: Dictation cleanup directive chain

    func testDefaultCleanupChainKeepsLegacyDirective() {
        let transcript = "um so i think we should ship it"
        XCTAssertEqual(
            PromptComposer.dictationDirective(
                for: transcript, directives: CleanupDirective.defaultChain
            ),
            PromptComposer.dictationDirective(for: transcript)
        )
        XCTAssertTrue(
            PromptComposer.dictationDirective(for: transcript)
                .contains(PromptComposer.dictationDirective)
        )
    }

    func testCustomCleanupChainListsStepsInOrderAndKeepsGuards() {
        let directive = PromptComposer.dictationDirective(
            for: "short note",
            directives: [.fixGrammar, .removeFiller]
        )

        XCTAssertTrue(directive.contains(PromptComposer.dictationCleanupBase))
        XCTAssertTrue(directive.contains("Never answer"))
        XCTAssertTrue(directive.contains("1. \(CleanupDirective.fixGrammar.promptDirective)"))
        XCTAssertTrue(directive.contains("2. \(CleanupDirective.removeFiller.promptDirective)"))
        // Short dictation still gets the single-paragraph layout rule.
        XCTAssertTrue(directive.contains("single paragraph"))
    }

    func testBulletPointsCardReplacesTheLayoutRule() {
        let directive = PromptComposer.dictationDirective(
            for: "short note",
            directives: [.removeFiller, .bulletPoints]
        )

        XCTAssertTrue(directive.contains(CleanupDirective.bulletPoints.promptDirective))
        XCTAssertFalse(directive.contains("single paragraph"))
        XCTAssertFalse(directive.contains("Break the result into paragraphs"))
    }

    func testEmptyCleanupChainKeepsOnlyTheGuards() {
        let directive = PromptComposer.dictationDirective(for: "short note", directives: [])

        XCTAssertTrue(directive.contains(PromptComposer.dictationCleanupBase))
        XCTAssertFalse(directive.contains("Apply these cleanup steps"))
        XCTAssertTrue(directive.contains("single paragraph"))
    }

    func testIntentPromptStillMatchesDirectiveOverload() {
        XCTAssertEqual(
            PromptComposer.userPrompt(intent: .shorten, text: "Words"),
            PromptComposer.userPrompt(directive: RewriteIntent.shorten.directive, text: "Words")
        )
    }
}
