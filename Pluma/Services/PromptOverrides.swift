import Foundation

/// One editable recipe prompt. `id` is the UserDefaults key suffix; `defaultText`
/// is the shipped copy so Reset can restore it.
struct RecipePrompt: Identifiable, Equatable, Sendable {
    let id: String
    let group: String
    let title: String
    let defaultText: String
}

/// Developer-page overrides for recipe directives. Empty or identical-to-shipped
/// values fall out of the store so an untouched install keeps byte-for-byte
/// shipped prompts.
enum PromptOverrides: Sendable {
    static let key = "pluma.promptOverrides"
    static let readerSummarizeID = "reader.summarize"

    private static let box = StoreBox()

    /// Tests replace this with a suite; production stays on `UserDefaults.standard`.
    static var store: UserDefaults {
        get {
            box.lock.lock()
            defer { box.lock.unlock() }
            return box.defaults
        }
        set {
            box.lock.lock()
            box.defaults = newValue
            box.lock.unlock()
        }
    }

    static var catalog: [RecipePrompt] {
        let rewrite = RewriteIntent.allCases.map { intent in
            RecipePrompt(
                id: intent.promptID,
                group: "Rewrite",
                title: intent.title,
                defaultText: intent.shippedDirective
            )
        }
        let autocomplete = CompletionDirective.allCases.map { directive in
            RecipePrompt(
                id: directive.promptID,
                group: "Autocomplete",
                title: directive.title,
                defaultText: directive.shippedPromptDirective
            )
        }
        let dictation = CleanupDirective.allCases.map { directive in
            RecipePrompt(
                id: directive.promptID,
                group: "Dictation",
                title: directive.title,
                defaultText: directive.shippedPromptDirective
            )
        }
        let reader = [
            RecipePrompt(
                id: readerSummarizeID,
                group: "Reader",
                title: "Summarize, then read",
                defaultText: PromptComposer.shippedReaderSummaryDirective
            )
        ]
        return rewrite + autocomplete + dictation + reader
    }

    static func text(for id: String, default fallback: String) -> String {
        let trimmed = map()[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return fallback
    }

    static func isCustom(_ id: String, default fallback: String) -> Bool {
        text(for: id, default: fallback) != fallback
    }

    static func set(_ text: String, for id: String, default fallback: String) {
        var current = map()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == fallback {
            current.removeValue(forKey: id)
        } else {
            current[id] = trimmed
        }
        store.set(current, forKey: key)
    }

    static func reset(_ id: String) {
        var current = map()
        current.removeValue(forKey: id)
        store.set(current, forKey: key)
    }

    static func resetAll() {
        store.removeObject(forKey: key)
    }

    static func hasAnyOverride() -> Bool {
        !map().isEmpty
    }

    private static func map() -> [String: String] {
        store.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}

private final class StoreBox: @unchecked Sendable {
    let lock = NSLock()
    var defaults: UserDefaults = .standard
}
