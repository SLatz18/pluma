import Foundation

/// Strips the wrappers a chat-tuned model adds around an edit, even when the
/// prompt forbids them (issue #39).
///
/// `PromptComposer.systemInstructions` already says "Do not add facts,
/// commentary, labels, quotation marks, or an explanation" and the user prompt
/// ends with "Return only the edited text". Apple Intelligence still returns
/// things like:
///
///     Sure! Here is the edited text:
///
///     Hey, so I think the numbers are off.
///
/// Observed live on 2026-07-30 through the clipboard flow, which pasted the
/// preamble straight into the writer's document. Prompt framing is necessary but
/// not sufficient, so parse defensively too.
///
/// Every rule here is deliberately conservative: wrongly stripping the writer's
/// own first line is far worse than leaving a preamble in. When a rule is not
/// confident, it does nothing.
enum RewriteOutputSanitizer {
    static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = strippingCodeFence(text)
        text = strippingEchoedSourceTags(text)
        text = strippingLeadingPreamble(text)
        text = strippingWrappingQuotes(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // The openers a chat model reaches for. Matched only at the very start of a
    // line that also reads like a preamble, never mid-text.
    private static let preambleOpeners = [
        "sure", "certainly", "of course", "here is", "here's", "here are",
        "okay", "ok", "absolutely", "got it", "i've", "i have", "i rewrote",
        "i edited", "the edited", "the rewritten", "revised text", "edited text",
        "rewritten text", "no problem", "happy to"
    ]

    /// Drops a leading line that announces the edit. Requires the line to look
    /// like an announcement AND for real content to follow, so a writer's own
    /// "Dear John:" or "Summary:" heading survives when it is the whole point.
    static func strippingLeadingPreamble(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return text }

        let first = lines[0].trimmingCharacters(in: .whitespaces)
        // An announcement is short and ends in a colon. A long first line is
        // prose, not a label, no matter how it starts.
        guard first.count <= 80, first.hasSuffix(":") else { return text }

        let lowered = first.lowercased()
        guard preambleOpeners.contains(where: { lowered.hasPrefix($0) }) else { return text }

        let remainder = lines
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Never return empty: if the "preamble" was the entire response, it was
        // the content.
        return remainder.isEmpty ? text : remainder
    }

    /// Some models echo the `<source>` markers from the prompt back out.
    static func strippingEchoedSourceTags(_ text: String) -> String {
        var result = text
        for tag in ["<source>", "</source>"] {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unwraps ```fenced``` output, keeping the inner body.
    static func strippingCodeFence(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else { return text }
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return text }
        lines.removeFirst()  // opening fence plus any language hint
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        let inner = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? text : inner
    }

    /// Removes quotes the model wrapped the whole edit in. Only when they are
    /// balanced and the interior has no other quote of the same kind, so a
    /// legitimately quoted sentence is left alone.
    static func strippingWrappingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'")]
        for (open, close) in pairs {
            guard
                text.count > 2,
                text.first == open,
                text.last == close
            else { continue }
            let interior = String(text.dropFirst().dropLast())
            guard !interior.contains(open), !interior.contains(close) else { continue }
            return interior.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
