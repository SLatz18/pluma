import XCTest
@testable import Rewrite

final class PromptComposerTests: XCTestCase {
    func testEveryIntentAddsItsDirective() {
        for intent in RewriteIntent.allCases {
            let prompt = PromptComposer.userPrompt(intent: intent, text: "Hello")
            XCTAssertTrue(prompt.contains(intent.directive))
        }
    }

    func testSourceTextIsDelimited() {
        let prompt = PromptComposer.userPrompt(
            intent: .improve,
            text: "Original words",
            boundary: "TEST-BOUNDARY"
        )

        XCTAssertTrue(
            prompt.contains(
                "---BEGIN SOURCE TEST-BOUNDARY---\nOriginal words\n---END SOURCE TEST-BOUNDARY---"
            )
        )
        XCTAssertTrue(prompt.contains("<rewrite>"))
        XCTAssertTrue(prompt.contains("<unchanged/>"))
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
