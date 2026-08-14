import SwiftUI

enum AutomationStep: String, CaseIterable, Sendable {
    case when = "WHEN"
    case then = "THEN"
    case result = "RESULT"
}

struct FeatureDefinition: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case rewrite
        case autocomplete
        case dictation
        case reader
    }

    let id: ID
    let name: String
    let symbolName: String
    let tint: PlumaTheme.FeatureColor
    let trigger: String
    let action: String
    let result: String
    let enabledStatus: String
    let disabledStatus: String

    static let rewrite = FeatureDefinition(
        id: .rewrite,
        name: "Rewrite",
        symbolName: "sparkles.rectangle.stack",
        tint: .rewrite,
        trigger: "Select text and press the shortcut",
        action: "Run your recipe pipeline",
        result: "Replace the selection, or test it here",
        enabledStatus: "Ready to rewrite selected text",
        disabledStatus: "Choose at least one recipe"
    )

    static let autocomplete = FeatureDefinition(
        id: .autocomplete,
        name: "Autocomplete",
        symbolName: "character.cursor.ibeam",
        tint: .autocomplete,
        trigger: "Pause while typing with enough context",
        action: "Show a suggestion at the caret",
        result: "Accept with Tab or dismiss with Escape",
        enabledStatus: "Watching for a text field",
        disabledStatus: "Autocomplete is off"
    )

    static let dictation = FeatureDefinition(
        id: .dictation,
        name: "Dictation",
        symbolName: "mic",
        tint: .dictation,
        trigger: "Hold the dictation shortcut",
        action: "Transcribe and optionally clean up speech",
        result: "Insert the words when the shortcut is released",
        enabledStatus: "Ready to dictate",
        disabledStatus: "Dictation is off"
    )

    static let reader = FeatureDefinition(
        id: .reader,
        name: "Reader",
        symbolName: "speaker.wave.2",
        tint: .reader,
        trigger: "Select text and press the shortcut",
        action: "Read it verbatim or summarize it",
        result: "Speak it aloud",
        enabledStatus: "Ready to read selected text",
        disabledStatus: "Reader is off"
    )

    static let all: [FeatureDefinition] = [.rewrite, .autocomplete, .dictation, .reader]
}
