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
            let profile = AppExtractionProfile.profile(for: target.bundleID)
            let lines = collectVisibleText(pid: target.pid, profile: profile)
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

    private nonisolated static func frontmostTarget(
    ) -> (pid: pid_t, name: String?, bundleID: String?)? {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return nil }
        return (app.processIdentifier, app.localizedName, bundleID)
    }

    private nonisolated static func collectVisibleText(
        pid: pid_t, profile: AppExtractionProfile
    ) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        guard
            let window = copyElement(appElement, kAXFocusedWindowAttribute)
                ?? copyElement(appElement, kAXMainWindowAttribute)
        else { return [] }

        // Apps that render their thread in a web view (Slack's Electron shell,
        // Mail's reading pane) put everything worth reading under an AXWebArea.
        // Rooting the walk there drops sidebars, toolbars, and — in Mail — the
        // inbox table that sits next to the reading pane in the same window.
        let root = profile.prefersWebAreaRoot
            ? (deepestWebArea(under: window) ?? window)
            : window

        var fragments: [Fragment] = []
        var visited = 0
        walk(root, depth: 0, visited: &visited, profile: profile, into: &fragments)
        return shapedLines(fragments, profile: profile)
    }

    /// Breadth-first search for the largest web area: Slack nests a small one
    /// for the search bar, so "first" is wrong — the message pane is the one
    /// with the most descendants worth visiting, approximated by pixel size.
    private nonisolated static func deepestWebArea(under window: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [window]
        var best: (element: AXUIElement, area: CGFloat)?
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let element = queue.removeFirst()
            visited += 1
            let role = copyString(element, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" {
                let area = pixelArea(of: element)
                if best == nil || area > best!.area {
                    best = (element, area)
                }
                continue // A web area's own children are walked later, in order.
            }
            if let children = copyChildren(element) {
                queue.append(contentsOf: children)
            }
        }
        return best?.element
    }

    private nonisolated static func pixelArea(of element: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return 0 }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return 0 }
        return size.width * size.height
    }

    /// One captured text node, tagged with enough tree context for the pure
    /// shaping pass to tell sender headings from message bodies.
    struct Fragment: Equatable, Sendable {
        let text: String
        /// True when the tree itself marked this line as a heading — Slack and
        /// Mail both expose sender names that way where they expose them at all.
        let isHeading: Bool
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
        profile: AppExtractionProfile,
        into fragments: inout [Fragment]
    ) {
        guard depth <= maximumDepth, visited <= maximumNodesVisited else { return }
        visited += 1

        let role = copyString(element, kAXRoleAttribute) ?? ""
        // Window chrome would drown the thread in "Reply" and "Search" labels.
        guard !chromeRoles.contains(role), !profile.skippedRoles.contains(role) else {
            return
        }
        // Some apps label their chrome panes (Slack: "Channel sidebar",
        // "Workspace switcher") rather than using chrome roles; skip whole
        // subtrees the profile names.
        if containerRoles.contains(role), !profile.skippedContainerDescriptions.isEmpty {
            let description = (copyString(element, kAXDescriptionAttribute) ?? "")
                .lowercased()
            if profile.skippedContainerDescriptions.contains(
                where: { description.contains($0) }
            ) { return }
        }

        if textRoles.contains(role) {
            appendText(from: element, role: role, into: &fragments)
        }

        guard let children = copyChildren(element) else { return }
        for child in children {
            guard visited <= maximumNodesVisited else { return }
            walk(child, depth: depth + 1, visited: &visited, profile: profile, into: &fragments)
        }
    }

    private nonisolated static func appendText(
        from element: AXUIElement,
        role: String,
        into fragments: inout [Fragment]
    ) {
        let raw = copyString(element, kAXValueAttribute)
            ?? copyString(element, kAXTitleAttribute)
            ?? (role == kAXStaticTextRole as String
                ? copyString(element, kAXDescriptionAttribute) : nil)
        guard let raw else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fragments.append(
            Fragment(
                text: String(trimmed.prefix(maximumLineLength)),
                isHeading: role == "AXHeading"
            )
        )
    }

    private nonisolated static let containerRoles: Set<String> = [
        kAXGroupRole as String,
        "AXList",
        kAXScrollAreaRole as String
    ]

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

    /// Filters per-app noise, then labels senders. Runs on captured fragments
    /// before the generic dedupe/truncation so the model reads "Alice: text"
    /// instead of a heading line floating above an unattributed message.
    nonisolated static func shapedLines(
        _ fragments: [Fragment], profile: AppExtractionProfile
    ) -> [String] {
        let kept = fragments.filter { !profile.isNoise($0.text) }
        return normalizedLines(senderLabeled(kept))
    }

    /// Where the tree marks a sender name as a heading, folds it into the
    /// next message line as "Alice: message". A heading followed by another
    /// heading (or nothing) stays as-is — better an unlabeled line than a
    /// wrongly attributed one.
    nonisolated static func senderLabeled(_ fragments: [Fragment]) -> [String] {
        var output: [String] = []
        var index = 0
        while index < fragments.count {
            let fragment = fragments[index]
            if fragment.isHeading,
               looksLikeSenderName(fragment.text),
               index + 1 < fragments.count,
               !fragments[index + 1].isHeading {
                output.append("\(fragment.text): \(fragments[index + 1].text)")
                index += 2
                continue
            }
            output.append(fragment.text)
            index += 1
        }
        return output
    }

    /// A sender heading is a short run of words with no sentence punctuation —
    /// "Alice Chen", not "Weekly report attached." Section headings that read
    /// like sentences must not swallow the line after them.
    nonisolated static func looksLikeSenderName(_ text: String) -> Bool {
        guard text.count <= 60, !text.isEmpty else { return false }
        guard text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?:;,")) == nil
        else { return false }
        return text.split(separator: " ").count <= 5
    }

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

    // MARK: Per-app extraction profiles

    /// What the generic AX walk should ignore or prefer in a specific app.
    /// The generic profile is deliberately empty: unknown apps keep today's
    /// behavior exactly.
    struct AppExtractionProfile: Sendable {
        /// Root the walk at the window's largest AXWebArea when one exists.
        let prefersWebAreaRoot: Bool
        /// Extra roles skipped wholesale, beyond the shared chrome roles.
        let skippedRoles: Set<String>
        /// Lowercased substrings of AXDescription on group/list/scroll-area
        /// containers whose whole subtree is chrome (sidebars, switchers).
        let skippedContainerDescriptions: [String]
        /// Lines matching any of these are dropped before shaping.
        let noisePatterns: [NSRegularExpression]

        nonisolated static let generic = AppExtractionProfile(
            prefersWebAreaRoot: false,
            skippedRoles: [],
            skippedContainerDescriptions: [],
            noisePatterns: []
        )

        /// Slack's Electron shell exposes one big web area; the sidebar and
        /// workspace switcher live in labeled containers inside it. Timestamps,
        /// reaction counts, and reply-count buttons are real text nodes that
        /// only waste budget.
        nonisolated static let slack = AppExtractionProfile(
            prefersWebAreaRoot: true,
            skippedRoles: [],
            skippedContainerDescriptions: [
                "channel sidebar", "workspace switcher", "history navigation",
                "primary view navigation", "search"
            ],
            noisePatterns: compiled([
                #"^\d{1,2}:\d{2}(\s?[AP]M)?$"#,
                #"^(Today|Yesterday) at \d{1,2}:\d{2}(\s?[AP]M)?$"#,
                #"^\d+ (repl(y|ies)|reaction[s]?)$"#,
                #"^(Add reaction|Reply in thread|New messages?|\(edited\))$"#,
                #"reacted with :[a-z0-9_+-]+:"#
            ])
        )

        /// Mail shows the inbox table and the reading pane in one window; the
        /// table (and the mailbox outline) must not leak into the thread. The
        /// message body itself is a web area.
        nonisolated static let mail = AppExtractionProfile(
            prefersWebAreaRoot: true,
            skippedRoles: [kAXTableRole as String, kAXOutlineRole as String],
            skippedContainerDescriptions: ["message list", "mailbox list", "favorites"],
            noisePatterns: compiled([
                #"^\d{1,2}:\d{2}(\s?[AP]M)?$"#,
                #"^(To|Cc|Bcc):$"#
            ])
        )

        nonisolated static func profile(for bundleID: String?) -> AppExtractionProfile {
            switch bundleID {
            case "com.tinyspeck.slackmacgap": return .slack
            case "com.apple.mail": return .mail
            default: return .generic
            }
        }

        nonisolated func isNoise(_ line: String) -> Bool {
            let range = NSRange(line.startIndex..., in: line)
            return noisePatterns.contains {
                $0.firstMatch(in: line, range: range) != nil
            }
        }

        private nonisolated static func compiled(_ patterns: [String]) -> [NSRegularExpression] {
            patterns.compactMap {
                try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
            }
        }
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
