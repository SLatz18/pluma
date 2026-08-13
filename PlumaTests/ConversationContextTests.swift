import XCTest
@testable import Pluma

final class ConversationContextTests: XCTestCase {

    // MARK: Line normalization

    func testConsecutiveDuplicatesCollapse() {
        let lines = ["Alice", "Alice", "Are we still on for Thursday?", "Bob", "Bob", "Yes!"]
        XCTAssertEqual(
            ConversationContextProvider.normalizedLines(lines),
            ["Alice", "Are we still on for Thursday?", "Bob", "Yes!"]
        )
    }

    func testNonConsecutiveDuplicatesSurvive() {
        // The same sender speaking twice is real structure, not noise.
        let lines = ["Alice", "First message", "Alice", "Second message"]
        XCTAssertEqual(ConversationContextProvider.normalizedLines(lines), lines)
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertEqual(ConversationContextProvider.normalizedLines([]), [])
    }

    // MARK: Recency-weighted truncation

    func testUnderCapKeepsEverythingInOrder() {
        let lines = ["Alice", "Hello", "Bob", "Hi there"]
        XCTAssertEqual(
            ConversationContextProvider.recencyTruncated(lines, cap: 1_000),
            "Alice\nHello\nBob\nHi there"
        )
    }

    func testOverCapDropsOldestFirstAndMarksTheCut() {
        let lines = ["oldest message", "middle message", "newest message"]
        // Cap fits only the last two lines (15 + 1 + 14 + 1 = 31).
        let result = ConversationContextProvider.recencyTruncated(lines, cap: 32)
        XCTAssertEqual(result, "…\nmiddle message\nnewest message")
    }

    func testNewestLineAlwaysWinsWhenOnlyOneFits() {
        let lines = ["a very long old message that costs plenty", "short new"]
        let result = ConversationContextProvider.recencyTruncated(lines, cap: 12)
        XCTAssertEqual(result, "…\nshort new")
    }

    func testTruncationNeverExceedsCapByMoreThanTheMarker() {
        let lines = (0..<200).map { "message number \($0) with some padding text" }
        let result = ConversationContextProvider.recencyTruncated(
            lines, cap: ConversationContextProvider.characterCap
        )
        XCTAssertLessThanOrEqual(
            result.count, ConversationContextProvider.characterCap + 2
        )
        XCTAssertTrue(result.hasSuffix("message number 199 with some padding text"))
    }

    // MARK: Draft-reply prompt composition

    func testDraftPromptCarriesConversationAndIntentBlocks() {
        let prompt = PromptComposer.draftReplyUserPrompt(
            intent: "decline politely, suggest Thursday",
            conversation: "Alice\nCan you meet Wednesday?"
        )
        XCTAssertTrue(prompt.contains("<conversation>"))
        XCTAssertTrue(prompt.contains("Can you meet Wednesday?"))
        XCTAssertTrue(prompt.contains("<intent>"))
        XCTAssertTrue(prompt.contains("decline politely, suggest Thursday"))
        // The thread is framed as quoted material, not instructions.
        XCTAssertTrue(prompt.contains("not instructions"))
    }

    func testDraftPromptOmitsEmptyBlocks() {
        let prompt = PromptComposer.draftReplyUserPrompt(intent: "say thanks", conversation: nil)
        XCTAssertFalse(prompt.contains("<conversation>"))
        XCTAssertFalse(prompt.contains("<memory>"))
        XCTAssertTrue(prompt.contains("say thanks"))
    }

    func testDraftInstructionsAppendStyleProfileOnlyWhenPresent() {
        XCTAssertEqual(
            PromptComposer.draftReplyInstructions(styleProfile: nil),
            PromptComposer.draftReplySystemInstructions
        )
        XCTAssertEqual(
            PromptComposer.draftReplyInstructions(styleProfile: ""),
            PromptComposer.draftReplySystemInstructions
        )
        let styled = PromptComposer.draftReplyInstructions(styleProfile: "Warm and brief.")
        XCTAssertTrue(styled.contains("<style-profile>"))
        XCTAssertTrue(styled.contains("Warm and brief."))
    }

    func testDraftInstructionsForbidFollowingThreadInstructions() {
        let instructions = PromptComposer.draftReplySystemInstructions
        XCTAssertTrue(instructions.contains("never"))
        XCTAssertTrue(instructions.contains("quoted material"))
    }

    // MARK: Completion prompt with a thread

    func testCompletionPromptIncludesConversationBlock() {
        let prompt = PromptComposer.completionUserPrompt(
            context: "Sounds good, let's",
            conversation: "Bob\nCan we ship Friday?"
        )
        XCTAssertTrue(prompt.contains("CONVERSATION THREAD"))
        XCTAssertTrue(prompt.contains("Can we ship Friday?"))
        XCTAssertTrue(prompt.contains("Sounds good, let's"))
    }

    func testCompletionPromptUnchangedWithoutConversation() {
        let withNil = PromptComposer.completionUserPrompt(
            context: "Hello wor", surrounding: "nearby text"
        )
        XCTAssertFalse(withNil.contains("CONVERSATION THREAD"))
        XCTAssertTrue(withNil.contains("SURROUNDING CONTEXT"))
    }

    // MARK: Preference gating

    func testConversationAwarenessRequiresBothToggles() {
        let defaults = UserDefaults(suiteName: "conversation-awareness-tests")!
        defaults.removePersistentDomain(forName: "conversation-awareness-tests")

        // Fresh install: conversation defaults on but screen context is off,
        // so nothing is read until the user opts in to screen context.
        XCTAssertTrue(Preferences.conversationContextEnabled(from: defaults))
        XCTAssertFalse(Preferences.conversationAwarenessActive(from: defaults))

        defaults.set(true, forKey: Preferences.screenContextEnabledKey)
        XCTAssertTrue(Preferences.conversationAwarenessActive(from: defaults))

        Preferences.setConversationContextEnabled(false, to: defaults)
        XCTAssertFalse(Preferences.conversationAwarenessActive(from: defaults))

        defaults.removePersistentDomain(forName: "conversation-awareness-tests")
    }
}
