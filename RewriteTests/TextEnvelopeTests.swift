import XCTest
@testable import Rewrite

final class TextEnvelopeTests: XCTestCase {
    func testSplitsBoundaryWhitespaceFromBody() {
        let envelope = TextEnvelope("\n  Original text \t")

        XCTAssertEqual(envelope?.prefix, "\n  ")
        XCTAssertEqual(envelope?.body, "Original text")
        XCTAssertEqual(envelope?.suffix, " \t")
    }

    func testRejectsWhitespaceOnlyText() {
        XCTAssertNil(TextEnvelope(" \n\t "))
    }

    func testReplacementPreservesBoundaryWhitespace() throws {
        let envelope = try XCTUnwrap(TextEnvelope("\nOriginal\n"))

        XCTAssertEqual(
            try envelope.replacingBody(with: "  Revised  "),
            "\nRevised\n"
        )
    }
}
