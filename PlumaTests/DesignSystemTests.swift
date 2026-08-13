import XCTest
@testable import Pluma

final class DesignSystemTests: XCTestCase {
    func testFeatureDefinitionsCoverEveryFeatureExactlyOnce() {
        XCTAssertEqual(
            Set(FeatureDefinition.all.map(\.id)),
            Set(FeatureDefinition.ID.allCases)
        )
        XCTAssertEqual(FeatureDefinition.all.map(\.name), ["Rewrite", "Autocomplete", "Dictation", "Reader"])
    }

    func testEveryFeatureDefinesTheWholeAutomationSentence() {
        for feature in FeatureDefinition.all {
            XCTAssertFalse(feature.trigger.isEmpty, "\(feature.name) is missing WHEN copy")
            XCTAssertFalse(feature.action.isEmpty, "\(feature.name) is missing THEN copy")
            XCTAssertFalse(feature.result.isEmpty, "\(feature.name) is missing RESULT copy")
            XCTAssertFalse(feature.enabledStatus.isEmpty)
            XCTAssertFalse(feature.disabledStatus.isEmpty)
        }
        XCTAssertEqual(AutomationStep.allCases.map(\.rawValue), ["WHEN", "THEN", "RESULT"])
    }

    func testOverlayStatusFactoriesMapSemanticTones() {
        let warning = OverlayPresentation.warning(
            systemImage: "hand.raised",
            message: "Permission needed",
            anchor: .zero
        )
        let failure = OverlayPresentation.failure(
            systemImage: "xmark",
            message: "Failed",
            anchor: .zero
        )

        assertStatus(warning, message: "Permission needed", tone: .warning)
        assertStatus(failure, message: "Failed", tone: .failure)
    }

    func testSharedSettingsDestinationsRemainProductFacing() {
        XCTAssertEqual(SettingsDestination.allCases.map(\.title), ["General", "Writing", "Privacy"])
        XCTAssertEqual(SettingsDestination.writing.symbolName, "brain")
        XCTAssertEqual(SettingsDestination.privacy.symbolName, "hand.raised")
    }

    private func assertStatus(
        _ presentation: OverlayPresentation,
        message expectedMessage: String,
        tone expectedTone: OverlayTone,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .status(_, message, tone, pulses) = presentation.content else {
            return XCTFail("Expected status presentation", file: file, line: line)
        }
        XCTAssertEqual(message, expectedMessage, file: file, line: line)
        XCTAssertEqual(tone, expectedTone, file: file, line: line)
        XCTAssertFalse(pulses, file: file, line: line)
    }
}
