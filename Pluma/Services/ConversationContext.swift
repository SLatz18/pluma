import AppKit
import ApplicationServices

/// The visible conversation thread in the frontmost app, captured transiently
/// for one model request. Never written to disk — the whole value of this
/// feature rests on that being true.
struct ConversationContext: Sendable {
    enum Source: String, Sendable {
        case accessibility
        case ocr
    }

    let source: Source
    let text: String
    let appName: String?
}

/// Walks the frontmost app's Accessibility tree to collect the ordered message
/// text the user can see — the whole Slack channel or mail thread, not one
/// screenful of OCR. Falls back to the existing screenshot-and-OCR capture for
/// apps whose AX trees expose little (Electron apps with accessibility off,
/// canvas-drawn views).
enum ConversationContextProvider {
    /// Enough for a long visible thread while staying well inside every
    /// provider's context budget once the prompt around it is added.
    static let characterCap = 6_000

    /// Below this the AX tree told us close to nothing — window chrome and a
    /// button label or two — and the OCR fallback will do better.
    static let minimumUsefulYield = 200

    static let maximumNodesVisited = 2_500
    static let maximumDepth = 40
    static let maximumLineLength = 400

    // MARK: Capture

    // Off the main actor on purpose: a deep AX walk is a burst of IPC round
    // trips and the OCR fallback captures and reads a screenshot. Neither may
    // stall typing.
    nonisolated static func capture() async -> ConversationContext? {
        guard let target = frontmostTarget() else { return nil }

        if AXIsProcessTrusted() {
            let lines = collectVisibleText(pid: target.pid)
            let text = recencyTruncated(lines, cap: characterCap)
            if text.count >= minimumUsefulYield {
                DebugLog.log("conversation context via AX: \(text.count) chars")
                return ConversationContext(
                    source: .accessibility, text: text, appName: target.name
                )
            }
            DebugLog.log(
                "AX conversation yield too small (\(text.count) chars); trying OCR",
                at: .verbose
            )
        }

        if let ocr = await ScreenContextProvider.surroundingText(), !ocr.isEmpty {
            DebugLog.log("conversation context via OCR fallback: \(ocr.count) chars")
            return ConversationContext(source: .ocr, text: ocr, appName: target.name)
        }
        return nil
    }

    /// Autocomplete asks on every pause; re-walking the same window's tree each
    /// time would double every completion's latency. One capture is reused while
    /// the user stays in the same window and it stays fresh.
    nonisolated static func cachedCapture(
        maxAge: Duration = .seconds(10)
    ) async -> ConversationContext? {
        guard let target = frontmostTarget() else { return nil }
        let key = "\(target.pid):\(focusedWindowTitle(pid: target.pid) ?? "")"

        if let cached = await Cache.shared.lookup(key: key, maxAge: maxAge) {
            return cached.context
        }
        let context = await capture()
        // Failures are cached too: an app that yields nothing would otherwise
        // be re-walked and re-screenshotted on every keystroke pause.
        await Cache.shared.store(context, for: key)
        return context
    }

    private actor Cache {
        static let shared = Cache()

        struct Entry {
            let context: ConversationContext?
            let at: ContinuousClock.Instant
        }

        private var key: String?
        private var entry: Entry?

        func lookup(key: String, maxAge: Duration) -> Entry? {
            guard
                self.key == key,
                let entry,
                ContinuousClock.Instant.now - entry.at < maxAge
            else { return nil }
            return entry
        }

        func store(_ context: ConversationContext?, for key: String) {
            self.key = key
            entry = Entry(context: context, at: .now)
        }
    }

    // MARK: AX walk

    private nonisolated static func frontmostTarget() -> (pid: pid_t, name: String?)? {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return nil }
        return (app.processIdentifier, app.localizedName)
    }

    private nonisolated static func collectVisibleText(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        guard
            let window = copyElement(appElement, kAXFocusedWindowAttribute)
                ?? copyElement(appElement, kAXMainWindowAttribute)
        else { return [] }

        var lines: [String] = []
        var visited = 0
        walk(window, depth: 0, visited: &visited, into: &lines)
        return normalizedLines(lines)
    }

    // Depth-first in child order, which is document order in every app that
    // matters here — so a Slack channel or mail thread comes out as the
    // messages read on screen, senders and timestamps interleaved with their
    // text, oldest first. That ordering is the "structure heuristic": the
    // model sees sender lines directly above their messages, exactly as the
    // user does.
    private nonisolated static func walk(
        _ element: AXUIElement,
        depth: Int,
        visited: inout Int,
        into lines: inout [String]
    ) {
        guard depth <= maximumDepth, visited <= maximumNodesVisited else { return }
        visited += 1

        let role = copyString(element, kAXRoleAttribute) ?? ""
        // Window chrome would drown the thread in "Reply" and "Search" labels.
        guard !chromeRoles.contains(role) else { return }

        if textRoles.contains(role) {
            appendText(from: element, role: role, into: &lines)
        }

        guard let children = copyChildren(element) else { return }
        for child in children {
            guard visited <= maximumNodesVisited else { return }
            walk(child, depth: depth + 1, visited: &visited, into: &lines)
        }
    }

    private nonisolated static func appendText(
        from element: AXUIElement,
        role: String,
        into lines: inout [String]
    ) {
        let raw = copyString(element, kAXValueAttribute)
            ?? copyString(element, kAXTitleAttribute)
            ?? (role == kAXStaticTextRole as String
                ? copyString(element, kAXDescriptionAttribute) : nil)
        guard let raw else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(String(trimmed.prefix(maximumLineLength)))
    }

    private nonisolated static let textRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        "AXHeading",
        "AXLink"
    ]

    private nonisolated static let chromeRoles: Set<String> = [
        kAXMenuBarRole as String,
        kAXMenuBarItemRole as String,
        kAXToolbarRole as String,
        kAXScrollBarRole as String
    ]

    // MARK: Text shaping (pure — exercised directly by tests)

    /// Collapses consecutive duplicate lines. Chat apps often expose the same
    /// string twice (a label and its value); repeating it only wastes budget.
    nonisolated static func normalizedLines(_ lines: [String]) -> [String] {
        var output: [String] = []
        for line in lines where line != output.last {
            output.append(line)
        }
        return output
    }

    /// Keeps the newest text when the thread exceeds the cap. Conversations
    /// read bottom-up in relevance — the message being replied to is the last
    /// one — so truncation drops the oldest lines first and marks the cut.
    nonisolated static func recencyTruncated(_ lines: [String], cap: Int) -> String {
        var kept: [String] = []
        var total = 0
        for line in lines.reversed() {
            let cost = line.count + 1
            if total + cost > cap { break }
            kept.append(line)
            total += cost
        }
        var result = kept.reversed().joined(separator: "\n")
        if kept.count < lines.count {
            result = "…\n" + result
        }
        return result
    }

    // MARK: AX plumbing

    private nonisolated static func focusedWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = copyElement(appElement, kAXFocusedWindowAttribute) else {
            return nil
        }
        return copyString(window, kAXTitleAttribute)
    }

    private nonisolated static func copyElement(
        _ element: AXUIElement, _ attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private nonisolated static func copyString(
        _ element: AXUIElement, _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let string = value as? String
        else { return nil }
        return string
    }

    private nonisolated static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &value
            ) == .success,
            let array = value as? [AnyObject]
        else { return nil }
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
    }
}
