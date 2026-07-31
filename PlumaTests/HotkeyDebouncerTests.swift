import XCTest
@testable import Pluma

final class HotkeyDebouncerTests: XCTestCase {
    func testFirstCallAlwaysFires() {
        var debouncer = HotkeyDebouncer(interval: 0.35)
        XCTAssertTrue(debouncer.shouldFire())
    }

    func testSecondCallWithinIntervalIsIgnored() {
        var debouncer = HotkeyDebouncer(interval: 0.35)
        XCTAssertTrue(debouncer.shouldFire())
        XCTAssertFalse(debouncer.shouldFire())
    }
}
