import XCTest

@MainActor
final class PlumaNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--pluma-ui-openai-state", "missing"
        ]
        app.launch()
    }

    func testOverviewNavigatesToAllAutomationFlows() {
        XCTAssertTrue(app.descendants(matching: .any)["overview-page"].waitForExistence(timeout: 5))

        for feature in ["rewrite", "autocomplete", "dictation", "reader"] {
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

    // Settings are sidebar pages in the main window — one surface, no second
    // window. ⌘, lands on General; the sidebar reaches AI, Writing, and Privacy.
    func testSettingsExposeGeneralAIWritingAndPrivacy() {
        XCTAssertTrue(app.descendants(matching: .any)["overview-page"].waitForExistence(timeout: 5))

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings-general"].waitForExistence(timeout: 3))

        for page in ["ai", "writing", "privacy"] {
            app.descendants(matching: .any)["nav-\(page)"].click()
            XCTAssertTrue(
                app.descendants(matching: .any)["settings-\(page)"].waitForExistence(timeout: 2)
            )
        }
    }

    func testAIControlCenterRoutesToDictationAndBackToExactSection() {
        let ai = app.descendants(matching: .any)["nav-ai"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5))
        ai.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings-ai"].waitForExistence(timeout: 3))

        let openDictation = app.descendants(matching: .any)["ai-open-dictation"]
        XCTAssertTrue(openDictation.waitForExistence(timeout: 3))
        openDictation.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["dictation-engine-controls"]
                .waitForExistence(timeout: 3)
        )
        let back = app.descendants(matching: .any)["contextual-back-ai"]
        XCTAssertTrue(back.waitForExistence(timeout: 2))
        back.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["ai-dictation-settings"]
                .waitForExistence(timeout: 3)
        )
    }

    // A shared-setting link must land on the page it names, not a generic
    // settings surface.
    func testSharedSettingLinkOpensThePageItNames() {
        XCTAssertTrue(app.descendants(matching: .any)["overview-page"].waitForExistence(timeout: 5))

        let privacyLink = app.descendants(matching: .any)["shared-setting-privacy"]
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 2))
        privacyLink.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings-privacy"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["nav-overview"].click()
        let aiLink = app.descendants(matching: .any)["shared-setting-ai"]
        XCTAssertTrue(aiLink.waitForExistence(timeout: 2))
        aiLink.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings-ai"].waitForExistence(timeout: 3))
    }

    // The app runs as an accessory with no main menu when every window is
    // closed, so the menu bar extra is the only route to Settings from a cold
    // start.
    func testMenuBarExtraOffersSettings() {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        let settingsItem = app.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3))
        settingsItem.click()

        XCTAssertTrue(app.descendants(matching: .any)["settings-general"].waitForExistence(timeout: 3))
    }
}
