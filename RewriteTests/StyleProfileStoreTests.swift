import XCTest
@testable import Rewrite

@MainActor
final class StyleProfileStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "style-profile.md")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testStripFrontmatterRemovesYamlBlock() {
        let skill = """
        ---
        name: writing-voice
        description: Voice model
        ---

        # Writing voice

        Dry, precise, no filler.
        """
        XCTAssertEqual(
            StyleProfileStore.stripFrontmatter(skill),
            "# Writing voice\n\nDry, precise, no filler."
        )
    }

    func testStripFrontmatterLeavesPlainTextAlone() {
        XCTAssertEqual(
            StyleProfileStore.stripFrontmatter("  just some text  "),
            "just some text"
        )
    }

    func testImportFromSkillFile() throws {
        try FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let skill = """
        ---
        name: voice
        ---
        Concise. Slightly dry.
        """
        try skill.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = StyleProfileStore(url: tempURL.deletingLastPathComponent().appending(path: "profile.md"))
        try store.importContents(of: tempURL)

        XCTAssertEqual(store.text, "Concise. Slightly dry.")
    }

    func testSetTextCapsLength() {
        let store = StyleProfileStore(url: tempURL)
        store.setText(String(repeating: "a", count: StyleProfileStore.maxCharacters + 500))
        XCTAssertEqual(store.text.count, StyleProfileStore.maxCharacters)
    }

    func testPersistsAndClears() {
        let store = StyleProfileStore(url: tempURL)
        store.setText("my voice")

        let reloaded = StyleProfileStore(url: tempURL)
        XCTAssertEqual(reloaded.text, "my voice")

        reloaded.clear()
        XCTAssertTrue(StyleProfileStore(url: tempURL).isEmpty)
    }

    func testCompletionInstructionsIncludeProfile() {
        let instructions = PromptComposer.completionInstructions(styleProfile: "Dry and brief")
        XCTAssertTrue(instructions.contains("<style-profile>\nDry and brief\n</style-profile>"))

        XCTAssertEqual(
            PromptComposer.completionInstructions(styleProfile: nil),
            PromptComposer.completionSystemInstructions
        )
    }
}
