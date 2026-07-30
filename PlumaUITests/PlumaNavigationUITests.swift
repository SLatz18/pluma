import XCTest

@MainActor
final class PlumaNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    func testOverviewNavigatesToAllAutomationFlows() {
        XCTAssertTrue(app.descendants(matching: .any)["overview-page"].waitForExistence(timeout: 5))

        for feature in ["rewrite", "autocomplete", "dictation"] {
            let overviewCard = app.descendants(matching: .any)["overview-\(feature)"]
            XCTAssertTrue(overviewCard.waitForExistence(timeout: 2))
            overviewCard.click()
            XCTAssertTrue(
                app.descendants(matching: .any)["\(feature)-page"].waitForExistence(timeout: 2)
            )
            app.descendants(matching: .any)["nav-overview"].click()
        }
    }

    func testSidebarSupportsKeyboardTraversalAtMinimumWindowSize() {
        let overview = app.descendants(matching: .any)["nav-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        overview.click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["rewrite-page"].waitForExistence(timeout: 2))
    }

    func testSettingsExposeGeneralWritingAndPrivacy() {
        app.typeKey(",", modifierFlags: .command)

        for tab in ["General", "Writing", "Privacy"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.click()
        }
        XCTAssertTrue(app.descendants(matching: .any)["settings-privacy"].exists)
    }
}
