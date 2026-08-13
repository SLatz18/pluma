import AppKit
import Foundation
import XCTest
@testable import Pluma

/// #48. Covers the parts of the clipboard fallback that do not need a live model
/// or a real global hotkey: preference round-tripping, shortcut conflict
/// detection, and PasteboardAccess's privacy-aware read path.
final class ClipboardFallbackTests: XCTestCase {
    // MARK: - Preferences

    func testClipboardFallbackIsOffByDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // It reads the general pasteboard, which can prompt, so it must never
        // enable itself.
        XCTAssertFalse(Preferences.clipboardFallbackEnabled(from: defaults))
    }

    func testClipboardFallbackTogglePersists() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        Preferences.setClipboardFallbackEnabled(true, to: defaults)
        XCTAssertTrue(Preferences.clipboardFallbackEnabled(from: defaults))

        Preferences.setClipboardFallbackEnabled(false, to: defaults)
        XCTAssertFalse(Preferences.clipboardFallbackEnabled(from: defaults))
    }

    func testClipboardShortcutDefaultsToCapsLockR() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(Preferences.clipboardShortcut(from: defaults), .clipboardDefault)
        XCTAssertEqual(Preferences.clipboardShortcut(from: defaults).display, "⇪R")
    }

    func testClipboardShortcutRoundTrips() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = GlobalShortcut(keyCode: 40, carbonModifiers: 4096, display: "⌃K")

        Preferences.saveClipboardShortcut(custom, to: defaults)

        XCTAssertEqual(Preferences.clipboardShortcut(from: defaults), custom)
    }

    func testClipboardShortcutIsIndependentOfTheOtherTwo() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = GlobalShortcut(keyCode: 40, carbonModifiers: 4096, display: "⌃K")

        Preferences.saveClipboardShortcut(custom, to: defaults)

        // Carbon keys them separately; a shared key would silently rebind another
        // feature's chord.
        XCTAssertEqual(Preferences.globalShortcut(from: defaults), .default)
        XCTAssertEqual(Preferences.dictationShortcut(from: defaults), .dictationDefault)
    }

    // MARK: - Conflict detection

    func testConflictIsReportedAgainstTheSelectionShortcut() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conflict = ClipboardRewriteController.conflict(for: .default, defaults: defaults)

        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Rewrite Selection") == true)
    }

    func testConflictIsReportedAgainstTheDictationShortcut() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conflict = ClipboardRewriteController.conflict(
            for: .dictationDefault,
            defaults: defaults
        )

        XCTAssertNotNil(conflict)
        XCTAssertTrue(conflict?.contains("Dictation") == true)
    }

    func testTheDefaultClipboardChordDoesNotConflict() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // ⇪R has to be free out of the box, or the feature is dead on arrival.
        XCTAssertNil(
            ClipboardRewriteController.conflict(for: .clipboardDefault, defaults: defaults)
        )
    }

    // MARK: - Safe Undo

    func testClipboardUndoAllowsAnUnchangedPasteboard() {
        XCTAssertTrue(
            ClipboardRewriteController.canSafelyRestoreClipboard(
                expectedChangeCount: 42,
                currentChangeCount: 42
            )
        )
    }

    func testClipboardUndoRefusesToOverwriteNewerCopiedContent() {
        XCTAssertFalse(
            ClipboardRewriteController.canSafelyRestoreClipboard(
                expectedChangeCount: 42,
                currentChangeCount: 43
            )
        )
        XCTAssertFalse(
            ClipboardRewriteController.canSafelyRestoreClipboard(
                expectedChangeCount: nil,
                currentChangeCount: 43
            )
        )
    }

    // MARK: - PasteboardAccess

    func testPreflightIsFalseForAnEmptyPasteboard() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        XCTAssertFalse(PasteboardAccess.preflightHasString(on: pasteboard))
    }

    func testPreflightIsTrueWhenPlainTextIsPresent() {
        let pasteboard = makePasteboard(containing: "hello")

        XCTAssertTrue(PasteboardAccess.preflightHasString(on: pasteboard))
    }

    func testReadReturnsTheStringWhenPresent() async throws {
        let pasteboard = makePasteboard(containing: "  Some copied text \n")

        let read = try await PasteboardAccess.readString(from: pasteboard)

        // Read is verbatim; TextEnvelope owns trimming so boundary whitespace
        // can be restored afterwards.
        XCTAssertEqual(read, "  Some copied text \n")
    }

    func testReadThrowsEmptyForWhitespaceOnlyContent() async {
        let pasteboard = makePasteboard(containing: " \n\t ")

        do {
            _ = try await PasteboardAccess.readString(from: pasteboard)
            XCTFail("Expected ReadError.empty")
        } catch let error as PasteboardAccess.ReadError {
            XCTAssertEqual(error, .empty)
        } catch {
            XCTFail("Expected ReadError.empty, got \(error)")
        }
    }

    func testReadThrowsEmptyForAnEmptyPasteboard() async {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        do {
            _ = try await PasteboardAccess.readString(from: pasteboard)
            XCTFail("Expected ReadError.empty")
        } catch let error as PasteboardAccess.ReadError {
            XCTAssertEqual(error, .empty)
        } catch {
            XCTFail("Expected ReadError.empty, got \(error)")
        }
    }

    func testWriteReplacesPasteboardContents() {
        let pasteboard = makePasteboard(containing: "before")

        PasteboardAccess.writeString("after", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "after")
    }

    // MARK: - Debouncer

    func testDebouncerSuppressesARepeatedPress() {
        var debouncer = HotkeyDebouncer(interval: 60)

        // Carbon repeats a held chord; without this a long press would queue
        // several rewrites of the same clipboard.
        XCTAssertTrue(debouncer.shouldFire())
        XCTAssertFalse(debouncer.shouldFire())
    }

    func testDebouncerAllowsAPressOnceTheIntervalHasPassed() {
        var debouncer = HotkeyDebouncer(interval: 0)

        XCTAssertTrue(debouncer.shouldFire())
        XCTAssertTrue(debouncer.shouldFire())
    }

    // MARK: - Helpers

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ClipboardFallbackTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makePasteboard(containing text: String? = nil) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("PlumaTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        if let text {
            pasteboard.setString(text, forType: .string)
        }
        return pasteboard
    }
}
