import AppKit
import Foundation
import XCTest
@testable import Pluma

final class RewriteServiceProviderTests: XCTestCase {
    func testSuccessfulRewriteReplacesPasteboardText() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(RewriteIntent.shorten.rawValue, forKey: Preferences.intentKey)

        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, intent, text, _ in
                "\(intent.rawValue): \(text)"
            }
        )
        let pasteboard = makePasteboard(containing: "Original text")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertNil(serviceError)
        XCTAssertEqual(pasteboard.string(forType: .string), "shorten: Original text")
    }

    func testBlankSelectionFailsWithoutReplacingPasteboard() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, _, _, _ in "Unexpected" }
        )
        let pasteboard = makePasteboard(containing: " \n ")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(
            serviceError as String?,
            RewriteEngineError.emptySelection.localizedDescription
        )
        XCTAssertEqual(pasteboard.string(forType: .string), " \n ")
    }

    func testBlankModelOutputDoesNotEraseSelection() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, _, _, _ in " \n " }
        )
        let pasteboard = makePasteboard(containing: "Keep this")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(
            serviceError as String?,
            RewriteEngineError.invalidResponse.localizedDescription
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep this")
    }

    func testSuccessfulRewritePreservesSelectionBoundaryWhitespace() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, _, text, _ in
                text == "Indented text" ? "Revised text" : "Unexpected input"
            }
        )
        let pasteboard = makePasteboard(containing: "\n  Indented text  \n")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertNil(serviceError)
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "\n  Revised text  \n"
        )
    }

    func testSlowRewriteTimesOutWithoutReplacingPasteboard() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 0.01,
            rewriteOperation: { _, _, _, _ in
                try await Task.sleep(for: .seconds(1))
                return "Too late"
            }
        )
        let pasteboard = makePasteboard(containing: "Keep this too")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(
            serviceError as String?,
            RewriteEngineError.serviceTimedOut.localizedDescription
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep this too")
    }

    // #1: a Service entry pins its action through NSUserData, so "Shorten" in
    // the Services menu shortens regardless of what the app has selected.
    func testUserDataPinsTheIntentInsteadOfTheSavedChain() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        Preferences.saveChain([.professional], to: defaults)

        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, intent, text, _ in "\(intent.rawValue): \(text)" }
        )
        let pasteboard = makePasteboard(containing: "Original text")
        var serviceError: NSString?

        provider.rewriteSelection(
            pasteboard,
            userData: RewriteIntent.shorten.rawValue,
            error: &serviceError
        )

        XCTAssertNil(serviceError)
        XCTAssertEqual(pasteboard.string(forType: .string), "shorten: Original text")
    }

    func testSelectedActionSentinelFallsBackToTheSavedChain() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        Preferences.saveChain([.professional], to: defaults)

        XCTAssertEqual(
            RewriteServiceProvider.chain(forUserData: "selectedAction", defaults: defaults),
            [.professional]
        )
        XCTAssertEqual(
            RewriteServiceProvider.chain(forUserData: nil, defaults: defaults),
            [.professional]
        )
        XCTAssertEqual(
            RewriteServiceProvider.chain(forUserData: "not-an-intent", defaults: defaults),
            [.professional]
        )
    }

    func testChainRunsEveryStepInOrder() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        Preferences.saveChain([.grammar, .shorten], to: defaults)

        let provider = RewriteServiceProvider(
            defaults: defaults,
            timeout: 1,
            rewriteOperation: { _, intent, text, _ in "\(text)|\(intent.rawValue)" }
        )
        let pasteboard = makePasteboard(containing: "Start")
        var serviceError: NSString?

        provider.rewriteSelection(pasteboard, userData: nil, error: &serviceError)

        XCTAssertNil(serviceError)
        XCTAssertEqual(pasteboard.string(forType: .string), "Start|grammar|shorten")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "RewriteServiceProviderTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makePasteboard(containing text: String) -> NSPasteboard {
        let name = NSPasteboard.Name("PlumaTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard
    }
}
