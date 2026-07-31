import AppKit
import XCTest
@testable import Pluma

final class PasteboardSnapshotTests: XCTestCase {
    func testRestorePreservesAllRepresentations() throws {
        let pasteboard = NSPasteboard(
            name: .init("PasteboardSnapshotTests.\(UUID().uuidString)")
        )
        let item = NSPasteboardItem()
        let richTextType = NSPasteboard.PasteboardType.rtf
        let richText = try XCTUnwrap("{\\rtf1 Original}".data(using: .utf8))
        XCTAssertTrue(item.setString("Original", forType: .string))
        XCTAssertTrue(item.setData(richText, forType: richTextType))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let snapshot = PasteboardSnapshot(pasteboard)

        XCTAssertTrue(PasteboardSnapshot.replaceString("Revised", on: pasteboard))
        XCTAssertTrue(snapshot.restore(to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .string), "Original")
        XCTAssertEqual(pasteboard.data(forType: richTextType), richText)
    }
}
