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
        let prompt = PromptComposer.userPrompt(intent: .improve, text: "Original words")

        XCTAssertTrue(prompt.contains("<source>\nOriginal words\n</source>"))
        XCTAssertTrue(prompt.contains("Return only the edited text."))
    }

    func testAppleIntelligenceIsTheDefaultProvider() {
        XCTAssertEqual(RewriteProviderChoice.defaultProvider, .appleIntelligence)
    }
}
