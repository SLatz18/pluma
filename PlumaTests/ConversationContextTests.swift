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

    // MARK: Per-app profiles

    private typealias Fragment = ConversationContextProvider.Fragment
    private typealias Profile = ConversationContextProvider.AppExtractionProfile

    func testProfileSelectionByBundleID() {
        XCTAssertTrue(Profile.profile(for: "com.tinyspeck.slackmacgap").prefersWebAreaRoot)
        XCTAssertTrue(Profile.profile(for: "com.apple.mail").prefersWebAreaRoot)
        XCTAssertFalse(Profile.profile(for: "com.example.other").prefersWebAreaRoot)
        XCTAssertFalse(Profile.profile(for: nil).prefersWebAreaRoot)
    }

    func testSlackNoiseLinesDrop() {
        let profile = Profile.slack
        for noise in [
            "9:41 AM", "12:03", "Today at 9:41 AM", "Yesterday at 12:03",
            "3 replies", "1 reply", "2 reactions", "Add reaction",
            "Reply in thread", "New messages", "(edited)"
        ] {
            XCTAssertTrue(profile.isNoise(noise), "expected noise: \(noise)")
        }
        for message in [
            "Are we still on for Thursday?", "Shipping at 9 tomorrow",
            "I added 3 replies to the doc"
        ] {
            XCTAssertFalse(profile.isNoise(message), "expected kept: \(message)")
        }
    }

    func testMailNoiseLinesDrop() {
        let profile = Profile.mail
        XCTAssertTrue(profile.isNoise("To:"))
        XCTAssertTrue(profile.isNoise("Cc:"))
        XCTAssertTrue(profile.isNoise("9:41 AM"))
        XCTAssertFalse(profile.isNoise("To: everyone — thanks for the patience"))
    }

    func testGenericProfileKeepsEverything() {
        XCTAssertFalse(Profile.generic.isNoise("9:41 AM"))
    }

    // MARK: Sender labeling

    func testHeadingSenderFoldsIntoNextLine() {
        let fragments = [
            Fragment(text: "Alice Chen", isHeading: true),
            Fragment(text: "Can you review the doc?", isHeading: false),
            Fragment(text: "Bob", isHeading: true),
            Fragment(text: "On it.", isHeading: false)
        ]
        XCTAssertEqual(
            ConversationContextProvider.senderLabeled(fragments),
            ["Alice Chen: Can you review the doc?", "Bob: On it."]
        )
    }

    func testSentenceLikeHeadingIsNotTreatedAsSender() {
        let fragments = [
            Fragment(text: "Weekly report attached.", isHeading: true),
            Fragment(text: "See numbers below", isHeading: false)
        ]
        XCTAssertEqual(
            ConversationContextProvider.senderLabeled(fragments),
            ["Weekly report attached.", "See numbers below"]
        )
    }

    func testConsecutiveHeadingsStayUnlabeled() {
        let fragments = [
            Fragment(text: "Alice", isHeading: true),
            Fragment(text: "Bob", isHeading: true),
            Fragment(text: "hello", isHeading: false)
        ]
        XCTAssertEqual(
            ConversationContextProvider.senderLabeled(fragments),
            ["Alice", "Bob: hello"]
        )
    }

    func testTrailingHeadingSurvivesAlone() {
        let fragments = [Fragment(text: "Alice", isHeading: true)]
        XCTAssertEqual(ConversationContextProvider.senderLabeled(fragments), ["Alice"])
    }

    func testShapedLinesFilterThenLabelThenDedupe() {
        let fragments = [
            Fragment(text: "Alice", isHeading: true),
            Fragment(text: "9:41 AM", isHeading: false),
            Fragment(text: "Lunch?", isHeading: false),
            Fragment(text: "Lunch?", isHeading: false),
            Fragment(text: "3 replies", isHeading: false)
        ]
        XCTAssertEqual(
            ConversationContextProvider.shapedLines(fragments, profile: .slack),
            ["Alice: Lunch?"]
        )
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
