import Foundation
import XCTest
@testable import Pluma

/// #39. The regression cases come from a live end-to-end run on 2026-07-30: the
/// clipboard flow pasted Apple Intelligence's conversational preamble straight
/// into the document. The prompt already forbade commentary; the model added it
/// anyway.
final class RewriteOutputSanitizerTests: XCTestCase {
    // MARK: - The observed failure

    func testStripsTheExactPreambleObservedLive() {
        let raw = """
        Sure! Here is the edited text:

        Hey, so I think the numbers are off, and we should probably fix them.
        """

        XCTAssertEqual(
            RewriteOutputSanitizer.sanitize(raw),
            "Hey, so I think the numbers are off, and we should probably fix them."
        )
    }

    func testValidatedOutputStripsThePreambleToo() throws {
        // validatedOutput is the seam both the Service path and the clipboard
        // path run through, so fixing it there covers both.
        let raw = "Here is the rewritten text:\n\nTightened prose."

        XCTAssertEqual(try RewriteRunner.validatedOutput(raw), "Tightened prose.")
    }

    func testEnvelopeReplacementStripsThePreambleAndKeepsWhitespace() throws {
        let envelope = TextEnvelope("\n  original text  \n")

        let result = try XCTUnwrap(envelope).replacingBody(
            with: "Sure, here is the edited text:\n\nrevised text"
        )

        // Boundary whitespace preserved, preamble gone.
        XCTAssertEqual(result, "\n  revised text  \n")
    }

    // MARK: - Preamble variants

    func testStripsCommonOpeners() {
        let cases = [
            "Certainly! Here is the edited text:\n\nBody.",
            "Of course. Here's the revised version:\n\nBody.",
            "Okay, here is the rewrite:\n\nBody.",
            "I've edited the text:\n\nBody.",
            "The edited text:\n\nBody.",
            "Rewritten text:\n\nBody."
        ]

        for raw in cases {
            XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), "Body.", "failed for: \(raw)")
        }
    }

    // MARK: - Conservatism: the writer's own text must survive

    func testKeepsAWriterHeadingThatEndsInAColon() {
        // "Summary:" is not in the opener list, so it is content.
        let raw = "Summary:\n\nWe shipped the thing."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testKeepsASalutation() {
        let raw = "Dear John:\n\nThanks for the note."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testKeepsALongFirstLineEvenIfItStartsLikeAPreamble() {
        // Long first lines are prose, not labels, however they open.
        let raw = "Here is the thing I keep trying to explain to everyone on the "
            + "team about scheduling:\n\nIt never works."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testKeepsAPreambleShapedLineWhenItIsTheOnlyContent() {
        // If stripping would empty the result, it was the content.
        let raw = "Here is the plan:"

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testKeepsASingleLineOutput() {
        let raw = "Just the rewritten sentence."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testDoesNotStripAPreambleShapedPhraseMidText() {
        let raw = "The report is done. Here is the summary: it went well."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    // MARK: - Fences, echoed tags, quotes

    func testStripsCodeFence() {
        XCTAssertEqual(
            RewriteOutputSanitizer.sanitize("```\nRevised text.\n```"),
            "Revised text."
        )
    }

    func testStripsCodeFenceWithLanguageHint() {
        XCTAssertEqual(
            RewriteOutputSanitizer.sanitize("```text\nRevised text.\n```"),
            "Revised text."
        )
    }

    func testStripsEchoedSourceTags() {
        XCTAssertEqual(
            RewriteOutputSanitizer.sanitize("<source>\nRevised text.\n</source>"),
            "Revised text."
        )
    }

    func testStripsWrappingQuotes() {
        XCTAssertEqual(RewriteOutputSanitizer.sanitize("\"Revised text.\""), "Revised text.")
        XCTAssertEqual(RewriteOutputSanitizer.sanitize("“Revised text.”"), "Revised text.")
    }

    func testKeepsQuotesWhenTheInteriorAlsoQuotes() {
        // Balanced outer quotes around text that itself quotes is probably the
        // writer's own construction, so leave it.
        let raw = "\"He said \"no\" twice.\""

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    func testKeepsAnApostropheOnlyString() {
        let raw = "It's fine."

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), raw)
    }

    // MARK: - Combined

    func testStripsFenceAndPreambleTogether() {
        let raw = "```\nSure! Here is the edited text:\n\nRevised body.\n```"

        XCTAssertEqual(RewriteOutputSanitizer.sanitize(raw), "Revised body.")
    }

    func testBlankOutputStillThrows() {
        XCTAssertThrowsError(try RewriteRunner.validatedOutput("   \n  ")) { error in
            XCTAssertEqual(
                (error as? RewriteEngineError)?.localizedDescription,
                RewriteEngineError.invalidResponse.localizedDescription
            )
        }
    }
}
