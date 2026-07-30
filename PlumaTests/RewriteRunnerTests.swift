import XCTest
@testable import Pluma

final class RewriteRunnerTests: XCTestCase {
    func testValidatedOutputTrimsModelWhitespace() throws {
        let output = try RewriteRunner.validatedOutput("  Revised sentence.\n")

        XCTAssertEqual(output, "Revised sentence.")
    }

    func testValidatedOutputRejectsBlankText() {
        XCTAssertThrowsError(try RewriteRunner.validatedOutput(" \n\t ")) { error in
            guard case RewriteEngineError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testServiceTimeoutsLeaveHeadroomForAppKit() {
        XCTAssertLessThan(RewriteTimeouts.serviceRequest, RewriteTimeouts.service)
        XCTAssertLessThan(RewriteTimeouts.service, 30)
    }
}
