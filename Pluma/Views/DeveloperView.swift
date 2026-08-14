import AppKit
import SwiftUI

/// The hidden page behind ↑ ↑ ↓ ↓ ← → ← →. Everything diagnostic lives here so
/// the consumer pages stay clean, and everything on it starts on `.onAppear`
/// and stops on `.onDisappear` so it costs nothing when you are not looking.
struct DeveloperView: View {
    @EnvironmentObject private var developer: DeveloperMode
    @EnvironmentObject private var dictation: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var credentials: OpenAICredentials

    @StateObject private var inspector = CaretInspector()
    @StateObject private var log = LogViewerModel()
    @State private var isComparing = false
    @State private var didCopyDebugInfo = false
    @State private var conversationPreview: String?
    @State private var conversationCountdown: Int?

    var body: some View {
        DSPage(
            title: "Developer",
            subtitle: "Diagnostics for the caret, the log, and transcription quality.",
            eyebrow: "cheat code"
        ) {
            caretCard
            promptEditorCard
            completionCard
            conversationCard
            componentGalleryCard
            logCard
            compareCard
        }
        .onAppear {
            inspector.onSample = { [weak developer] caret in
                developer?.traceCaret(caret)
            }
            inspector.start()
            log.start()
        }
        .onDisappear {
            inspector.stop()
            log.stop()
        }
        .sheet(isPresented: $isComparing) {
            CleanupComparisonView()
        }
    }

    // MARK: Recipe prompts

    private var promptEditorCard: some View {
        PromptEditorCard()
    }

    // MARK: Component gallery

    private var componentGalleryCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.large) {
                header(
                    symbol: "square.grid.3x3",
                    tint: .accentColor,
                    title: "Component gallery",
                    detail: "Shared states and the pure-AppKit overlay renderer."
                )

                Divider()

                HStack(spacing: DS.Spacing.small) {
                    DSBadge(text: "Normal")
                    DSBadge(text: "Selected", tone: .success, systemImage: "checkmark")
                    DSBadge(text: "Permission", tone: .attention, systemImage: "hand.raised")
                    DSBadge(text: "Error", tone: .failure, systemImage: "exclamationmark.triangle")
                }

                HStack(spacing: DS.Spacing.small) {
                    Button("Primary") {}
                        .buttonStyle(.borderedProminent)
                    Button("Disabled") {}
                        .disabled(true)
                    Button("Loading…") {}
                        .disabled(true)
                    Button("Delete", role: .destructive) {}
                }

                VStack(spacing: DS.Spacing.small) {
                    DSStatusIndicator(tone: .success, text: "Ready")
                    DSStatusIndicator(tone: .recording, text: "Recording")
                    DSStatusIndicator(tone: .attention, text: "Permission needed")
                    DSStatusIndicator(tone: .failure, text: "Something failed")
                }

                DSEmptyState(
                    title: "Nothing here yet",
                    detail: "An empty state uses the same inset surface.",
                    systemImage: "tray"
                )

                Divider()

                Text("Floating pill")
                    .font(DS.cardTitle)

                HStack(spacing: DS.Spacing.small) {
                    Button("Suggestion") {
                        developer.previewOverlay(
                            .suggestion(text: "finish this thought", anchor: previewAnchor)
                        )
                    }
                    Button("Dictation") {
                        developer.previewOverlay(
                            .dictation(transcript: "the latest words stay visible", anchor: previewAnchor)
                        )
                    }
                    Button("Progress") {
                        developer.previewOverlay(
                            .status(
                                systemImage: "sparkles",
                                message: "Rewriting 2 of 3…",
                                tone: .accent,
                                anchor: previewAnchor
                            )
                        )
                    }
                    Button("Warning") {
                        developer.previewOverlay(
                            .warning(
                                systemImage: "hand.raised",
                                message: "Permission needed",
                                anchor: previewAnchor
                            )
                        )
                    }
                    Button("Failure") {
                        developer.previewOverlay(
                            .failure(
                                systemImage: "exclamationmark.triangle",
                                message: "This field rejected the edit",
                                anchor: previewAnchor
                            )
                        )
                    }
                    Button("Hide") {
                        developer.hideOverlayPreview()
                    }
                }
                .controlSize(.small)
            }
        }
        .accessibilityIdentifier("developer-component-gallery")
    }

    private var previewAnchor: CGPoint {
        SuggestionOverlayController.mouseTopLeftPoint()
    }

    // MARK: Caret

    private var caretCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 14) {
                header(
                    symbol: "cursorarrow.rays",
                    tint: DS.Feature.autocomplete.color,
                    title: "Caret inspector",
                    detail: "What the ghost-text code sees in the last field you typed in."
                )

                if let readout = inspector.readout {
                    Divider()
                    caretReadout(readout)
                } else {
                    Text("Type in another app, then come back — pluma's own fields are skipped.")
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                }

                Divider()

                DSToggleRow(
                    title: "Draw caret box on screen",
                    detail: "Red where the caret was found, blue dashed where ghost text landed.",
                    isOn: $developer.isTracingEnabled
                )
            }
        }
    }

    // MARK: Completion tuning

    // These four decide how much a suggestion says and how eagerly it asks, and
    // the only way to judge them is to type under them. They live here rather
    // than in Settings because the right values are found by experiment, not
    // chosen by preference.
    private var completionCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 14) {
                header(
                    symbol: "slider.horizontal.3",
                    tint: DS.Feature.autocomplete.color,
                    title: "Completion tuning",
                    detail: "Takes effect on the next suggestion — no restart."
                )

                Divider()

                stepperRow(
                    title: "Words in the pill",
                    detail: "Longest suggestion offered when the sentence has direction.",
                    value: $autocomplete.tuning.phraseWords,
                    range: CompletionTuning.phraseWordRange,
                    format: { "\($0) words" }
                )

                stepperRow(
                    title: "Words when unsure",
                    detail: "Cap once there is too little written to commit to a clause.",
                    value: $autocomplete.tuning.briefWords,
                    range: CompletionTuning.briefWordRange,
                    format: { "\($0) words" }
                )

                stepperRow(
                    title: "Pause before asking",
                    detail: "Typing this long without a keystroke sends the request. Shorter feels quicker and cancels more.",
                    value: $autocomplete.tuning.debounceMilliseconds,
                    range: CompletionTuning.debounceRange,
                    step: 50,
                    format: { "\($0) ms" }
                )

                stepperRow(
                    title: "Minimum context",
                    detail: "Characters that must be written before anything is suggested.",
                    value: $autocomplete.tuning.minimumContext,
                    range: CompletionTuning.minimumContextRange,
                    step: 2,
                    format: { "\($0) characters" }
                )

                Divider()

                DSToggleRow(
                    title: "Use Apple Intelligence for spelling",
                    detail: "On by default. Uses the on-device model with preceding words and grammar. Turn off to compare against the Mac spelling dictionary instead. Shares one Apple Intelligence session with rewrite and autocomplete.",
                    isOn: Binding(
                        get: { autocomplete.spellCorrectionEngine == .appleIntelligence },
                        set: { on in
                            autocomplete.spellCorrectionEngine = on ? .appleIntelligence : .dictionary
                        }
                    ),
                    disabled: !autocomplete.spellCorrectionEnabled || !autocomplete.isPermissionGranted
                )

                Divider()

                HStack {
                    Text(autocomplete.tuning == .standard ? "Shipped values" : "Changed from shipped")
                        .font(DS.meta)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Reset") { autocomplete.tuning = .standard }
                        .disabled(autocomplete.tuning == .standard)
                }
            }
        }
    }

    private func stepperRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        format: @escaping (Int) -> String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.cardBody)
                Text(detail)
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(format(value.wrappedValue))
                .font(DS.meta.monospacedDigit())
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func caretReadout(_ readout: CaretReadout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Field", "\(readout.appName) — \(readout.role)")
            if let caret = readout.caret {
                row("Probe won", caret.source.title)
                row("Caret rect", FocusedFieldTracker.describe(caret.rect))
            } else {
                row("Probe won", "none — every probe failed")
            }
            if let fontSize = readout.fontSize {
                row("Font size", "\(Int(fontSize)) pt")
            }
            if let budget = readout.widthBudget {
                row("Width budget", "\(Int(budget)) pt")
            }
            row("Caret at", "offset \(readout.caretLocation)")

            HStack(spacing: 6) {
                Circle()
                    .fill(readout.allowsGhostText ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(readout.verdict)
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(DS.meta)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    // MARK: Conversation context

    // The trust panel for conversation awareness: exactly what pluma would
    // hand the model, captured on demand and shown here — never stored.
    private var conversationCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 14) {
                header(
                    symbol: "text.bubble",
                    tint: DS.Feature.dictation.color,
                    title: "Conversation context preview",
                    detail: "See the thread text pluma extracts from the frontmost app — Accessibility first, OCR fallback."
                )

                HStack(spacing: 10) {
                    Button(
                        conversationCountdown.map { "Switch to the app… \($0)" }
                            ?? "Capture in 5 seconds"
                    ) {
                        captureConversationPreview()
                    }
                    .disabled(conversationCountdown != nil)

                    Text("Click, then bring Slack, Mail, or Messages to the front.")
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .controlSize(.small)

                if let conversationPreview {
                    ScrollView {
                        Text(conversationPreview)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 180)
                    .background(
                        DS.insetBackground,
                        in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                    )
                }
            }
        }
    }

    private func captureConversationPreview() {
        conversationCountdown = 5
        Task {
            for remaining in stride(from: 4, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                conversationCountdown = remaining
            }
            let context = await ConversationContextProvider.capture()
            conversationCountdown = nil
            if let context {
                conversationPreview = "Source: \(context.source.rawValue)"
                    + " · App: \(context.appName ?? "unknown")"
                    + " · \(context.text.count) chars\n\n"
                    + context.text
            } else {
                conversationPreview = "Nothing captured. Another app must be frontmost, "
                    + "and pluma needs Accessibility (or Screen Recording for the OCR fallback)."
            }
        }
    }

    // MARK: Log

    private var logCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 14) {
                header(
                    symbol: "doc.text.magnifyingglass",
                    tint: DS.Feature.shortcut.color,
                    title: "Diagnostics log",
                    detail: "Live tail of autocomplete-debug.log."
                )

                HStack(spacing: 10) {
                    Picker("Detail", selection: $developer.logLevel) {
                        ForEach(DebugLog.Level.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)

                    TextField("Filter", text: $log.filter)
                        .textFieldStyle(.roundedBorder)

                    Button("Clear") { log.clear() }
                    Button("Open in editor") { NSWorkspace.shared.open(DebugLog.url) }
                }
                .controlSize(.small)

                Text(developer.logLevel.detail)
                    .font(DS.meta)
                    .foregroundStyle(.secondary)

                logLines

                HStack {
                    Button {
                        copyDebugInfo()
                    } label: {
                        Label(
                            didCopyDebugInfo ? "Copied" : "Copy debug info",
                            systemImage: didCopyDebugInfo ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .controlSize(.small)
                    Spacer()
                    Text("\(log.filteredLines.count) lines")
                        .font(DS.meta)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var logLines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(log.filteredLines) { line in
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .frame(height: 220)
            .background(DS.insetBackground, in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous))
            .onChange(of: log.filteredLines.last?.id) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    // MARK: Compare

    private var compareCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 14) {
                header(
                    symbol: "waveform.badge.magnifyingglass",
                    tint: DS.Feature.dictation.color,
                    title: "Compare transcription and cleanup",
                    detail: "Record a sample and see every provider's output side by side."
                )
                HStack {
                    Button("Compare…") { isComparing = true }
                        .disabled(!credentials.hasKey)
                    if !credentials.hasKey {
                        Text("Needs an OpenAI key — the comparison runs both engines.")
                            .font(DS.meta)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Shared

    private func header(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DSIconTile(systemImage: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DS.cardTitle)
                Text(detail)
                    .font(DS.cardBody)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // Everything needed to make "ghost text is off in Slack" actionable.
    private func copyDebugInfo() {
        var report = ["# pluma debug info"]

        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        report.append("App: \(version) (\(build))")
        report.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        report.append("Accessibility trusted: \(AccessibilityPermission.shared.isTrusted)")
        report.append("Screen recording: \(ScreenContextProvider.shared.isPermitted)")
        report.append("Microphone: \(dictation.isMicPermitted)")
        report.append("Dictation provider: \(dictation.provider.rawValue)")
        report.append("Cleanup provider: \(dictation.cleanupProvider.rawValue)")
        report.append("Dictation shortcut: \(dictation.shortcut.display)")
        report.append("Log level: \(developer.logLevel.title)")

        if let readout = inspector.readout {
            report.append("")
            report.append("## Last caret readout")
            report.append("Field: \(readout.appName) — \(readout.role)")
            if let caret = readout.caret {
                report.append("Probe: \(caret.source.title)")
                report.append("Rect: \(FocusedFieldTracker.describe(caret.rect))")
            } else {
                report.append("Probe: none")
            }
            if let fontSize = readout.fontSize { report.append("Font: \(Int(fontSize)) pt") }
            if let budget = readout.widthBudget { report.append("Budget: \(Int(budget)) pt") }
            report.append("Verdict: \(readout.verdict)")
        }

        report.append("")
        report.append("## Last log lines")
        report.append(contentsOf: log.lines.suffix(50).map(\.text))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.joined(separator: "\n"), forType: .string)

        didCopyDebugInfo = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyDebugInfo = false
        }
    }
}
