import XCTest
@testable import Rewrite

final class HotkeyStatusTests: XCTestCase {
    func testUnavailableStatusUsesWarningSymbol() {
        XCTAssertEqual(HotkeyStatus.unavailable.tier, .unavailable)
        XCTAssertEqual(HotkeyStatus.unavailable.symbolName, "exclamationmark.triangle")
    }

    func testEnhancedStatusUsesEnhancedSymbol() {
        XCTAssertEqual(HotkeyStatus.enhanced.tier, .enhanced)
        XCTAssertEqual(HotkeyStatus.enhanced.symbolName, "keyboard.badge.ellipsis")
    }
}
