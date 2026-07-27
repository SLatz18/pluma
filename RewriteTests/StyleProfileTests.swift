import XCTest
@testable import Rewrite

final class StyleProfileTests: XCTestCase {
    func testNoStyleKeepsBaseInstructions() {
        let base = PromptComposer.systemInstructions()
        let withNone = PromptComposer.systemInstructions(for: .none)
        XCTAssertEqual(base, withNone)
        XCTAssertFalse(withNone.contains("STYLE PROFILE"))
    }

    func testProfileAddsDirectiveBannedPhrasesAndGlossary() {
        let profile = StyleProfile(
            id: "test",
            name: "Test Voice",
            summary: "test",
            directive: "Always be direct.",
            bannedPhrases: ["circle back"],
            glossary: [.init(avoid: "MAC", preferred: "Mac")]
        )

        let instructions = PromptComposer.systemInstructions(for: profile)
        XCTAssertTrue(instructions.contains("STYLE PROFILE: Test Voice"))
        XCTAssertTrue(instructions.contains("Always be direct."))
        XCTAssertTrue(instructions.contains("circle back"))
        XCTAssertTrue(instructions.contains("Use \"Mac\" instead of \"MAC\""))
        // Base safety rules survive composition
        XCTAssertTrue(instructions.contains("never as"))
    }

    func testBuiltInsHaveUniqueIDsAndNoStyleIsFirst() {
        let ids = StyleProfile.builtIns.map(\.id)
        XCTAssertEqual(ids.first, StyleProfile.none.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testManagedProfilesReplaceCustomAndAreFlagged() throws {
        let suite = UserDefaults(suiteName: "StyleProfileTests.managed")!
        defer { suite.removePersistentDomain(forName: "StyleProfileTests.managed") }

        let managed = StyleProfile(
            id: "corp",
            name: "Corp Voice",
            summary: "managed",
            directive: "Follow the house style.",
            bannedPhrases: [],
            glossary: []
        )
        let payload = try JSONEncoder().encode([managed])
        suite.set(String(data: payload, encoding: .utf8), forKey: StyleProfileStore.managedProfilesKey)

        let profiles = StyleProfileStore.availableProfiles(defaults: suite)
        XCTAssertEqual(profiles.count, 2) // none + managed
        XCTAssertEqual(profiles.last?.id, "corp")
        XCTAssertTrue(profiles.last?.isManaged ?? false)
    }

    func testMalformedManagedPayloadFallsBackToBuiltIns() {
        let suite = UserDefaults(suiteName: "StyleProfileTests.bad")!
        defer { suite.removePersistentDomain(forName: "StyleProfileTests.bad") }
        suite.set("{not json", forKey: StyleProfileStore.managedProfilesKey)

        let profiles = StyleProfileStore.availableProfiles(defaults: suite)
        XCTAssertTrue(profiles.contains(StyleProfile.plainBusiness))
    }

    func testWordDifferCountsAdjacentReplacementOnce() {
        let segments = WordDiffer.diff(
            original: "I send the draft yesterday",
            revised: "I sent the draft yesterday"
        )
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }

    func testWordDifferIdenticalTextHasNoChanges() {
        let segments = WordDiffer.diff(original: "all good here", revised: "all good here")
        XCTAssertEqual(WordDiffer.changeCount(segments), 0)
    }
}
