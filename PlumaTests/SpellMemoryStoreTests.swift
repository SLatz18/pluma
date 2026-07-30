import XCTest
@testable import Pluma

@MainActor
final class SpellMemoryStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appending(path: "pluma-spell-memory-tests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testRecordsAndLooksUpCaseInsensitively() {
        let store = SpellMemoryStore(url: tempURL)
        store.record(misspelling: "teh", replacement: "the")
        XCTAssertEqual(store.lookup("teh"), "the")
        XCTAssertEqual(store.lookup("Teh"), "The")
        XCTAssertEqual(store.lookup("TEH"), "THE")
        XCTAssertEqual(store.count, 1)
    }

    func testIgnoresIdenticalReplacement() {
        let store = SpellMemoryStore(url: tempURL)
        store.record(misspelling: "the", replacement: "the")
        XCTAssertEqual(store.count, 0)
    }

    func testIgnoresUnrelatedReplacement() {
        let store = SpellMemoryStore(url: tempURL)
        store.record(misspelling: "separ", replacement: "church")
        XCTAssertEqual(store.count, 0)
    }

    func testPersistsAcrossReload() {
        SpellMemoryStore(url: tempURL).record(
            misspelling: "adminipera", replacement: "administration"
        )
        let reloaded = SpellMemoryStore(url: tempURL)
        XCTAssertEqual(reloaded.lookup("adminipera"), "administration")
    }

    func testClear() {
        let store = SpellMemoryStore(url: tempURL)
        store.record(misspelling: "recieve", replacement: "receive")
        store.clear()
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.lookup("recieve"))
    }

    func testPreferenceDefaultsOn() {
        let suite = "pluma.tests.spellMemory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(Preferences.spellMemoryEnabled(from: defaults))
        Preferences.setSpellMemoryEnabled(false, to: defaults)
        XCTAssertFalse(Preferences.spellMemoryEnabled(from: defaults))
    }
}
