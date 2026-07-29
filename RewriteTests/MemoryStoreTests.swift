import XCTest
@testable import Rewrite

@MainActor
final class MemoryStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "memory.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testRecordAndDigestNewestFirst() {
        let store = MemoryStore(url: tempURL)
        store.record("first phrase")
        store.record("second phrase")

        let digest = store.digest()
        XCTAssertNotNil(digest)
        XCTAssertTrue(digest!.contains("- second phrase"))
        XCTAssertLessThan(
            digest!.range(of: "second")!.lowerBound,
            digest!.range(of: "first")!.lowerBound
        )
    }

    func testRecordSkipsConsecutiveDuplicatesAndShortText() {
        let store = MemoryStore(url: tempURL)
        store.record("same")
        store.record("same")
        store.record("ok")

        XCTAssertEqual(store.count, 1)
    }

    func testDigestDeduplicatesNonConsecutive() {
        let store = MemoryStore(url: tempURL)
        store.record("alpha")
        store.record("beta")
        store.record("alpha")

        let digest = store.digest()!
        XCTAssertEqual(digest.components(separatedBy: "- alpha").count - 1, 1)
    }

    func testClear() {
        let store = MemoryStore(url: tempURL)
        store.record("something")
        store.clear()

        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.digest())
    }

    func testPersistsAcrossInstances() {
        MemoryStore(url: tempURL).record("remember me")

        let reloaded = MemoryStore(url: tempURL)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.entries.first?.text, "remember me")
    }

    func testCapsAtMaxEntries() {
        let store = MemoryStore(url: tempURL)
        for index in 1...320 {
            store.record("phrase \(index)")
        }

        XCTAssertEqual(store.count, 300)
        XCTAssertEqual(store.entries.first?.text, "phrase 21")
        XCTAssertEqual(store.entries.last?.text, "phrase 320")
    }
}
