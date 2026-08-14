import CoreFoundation
import XCTest
@testable import Pluma

final class AXTextInsertionTests: XCTestCase {
    func testCurrentTextReadsUTF16Range() {
        let value = "Hello 👋 world"
        let location = ("Hello " as NSString).length
        let length = ("👋" as NSString).length

        XCTAssertEqual(
            AXTextInsertion.currentText(
                in: value,
                range: CFRange(location: location, length: length)
            ),
            "👋"
        )
    }

    func testCurrentTextRejectsOutOfBoundsRange() {
        XCTAssertNil(
            AXTextInsertion.currentText(
                in: "short",
                range: CFRange(location: 4, length: 10)
            )
        )
    }
}
