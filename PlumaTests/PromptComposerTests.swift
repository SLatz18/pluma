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

    func testIntentPromptStillMatchesDirectiveOverload() {
        XCTAssertEqual(
            PromptComposer.userPrompt(intent: .shorten, text: "Words"),
            PromptComposer.userPrompt(directive: RewriteIntent.shorten.directive, text: "Words")
        )
    }
}
