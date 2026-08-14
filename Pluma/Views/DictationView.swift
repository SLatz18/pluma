import SwiftUI

struct DictationView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var credentials: OpenAICredentials
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var navigation = MainNavigation.shared

    @State private var isRecording = false
    @State private var isRecordingDraft = false
    @State private var ollamaModels: [String] = []

    /// The stored model stays selectable even when Ollama no longer lists it,
    /// so the picker never renders blank.
    private var ollamaPickerOptions: [String] {
        if controller.ollamaModel.isEmpty || ollamaModels.contains(controller.ollamaModel) {
            return ollamaModels
        }
        return [controller.ollamaModel] + ollamaModels
    }
    @State private var showAdvanced = false
    @FocusState private var isEnginePickerFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        DSFeaturePage(
            .dictation,
            subtitle: "Hold the shortcut and talk. Release it to insert your words.",
            scrollTarget: featureScrollTarget
        ) {
            DSContextualBackLink(page: .dictation)

            heroCard

            shortcutCard

            cleanupRecipeSection

            draftReplySection

            transcriptionSection

            DSSharedSettingLink(
                title: "Shared screen context",
                value: autocomplete.screenContextEnabled
                    ? "On · improves names and visible terms"
                    : "Off",
                systemImage: "rectangle.dashed.badge.record",
                destination: .writing
            )
            .dsCard()

            DSPageFootnote(text: privacyNote)
        }
        .task {
            ollamaModels = (try? await OllamaEngine().availableModels()) ?? []
            // Seed only an empty selection; this key is shared with the writing
            // engine, so replacing a stored value here would change that too.
            if controller.ollamaModel.isEmpty, let first = ollamaModels.first {
                controller.ollamaModel = first
            }
        }
        .onAppear { applyNavigationFocus(navigation.focus) }
        .onChange(of: navigation.focus) { _, focus in
            applyNavigationFocus(focus)
        }
        .onChange(of: credentials.revision) {
            Task { await controller.prepare() }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        DSFeatureHero(
            systemImage: "mic",
            tint: DS.Feature.dictation.color,
            title: "Push-to-talk, anywhere",
            detail: "Recording runs only while the shortcut is held. Nothing is inserted until you let go, so partial guesses never reach your document.",
            isOn: $controller.isEnabled,
            toggleLabel: "Dictation",
            statusColor: statusColor,
            statusText: statusText,
            notice: controller.isMicPermitted ? nil : DSNoticeRow(
                systemImage: "mic.slash",
                tint: .orange,
                text: "Dictation needs microphone access.",
                actionTitle: "Grant Microphone Access…"
            ) {
                Task { await controller.requestMicrophonePermission() }
            }
        )
    }

    // MARK: Shortcut

    private var shortcutCard: some View {
        DSShortcutCard(
            systemImage: "keyboard",
            title: "Hold to talk",
            detail: isRecording
                ? "Press and hold the new shortcut. Esc cancels."
                : "Hold Caps Lock Space when Caps shortcuts are on in Settings, or record any shortcut.",
            shortcut: controller.shortcut,
            isRecording: $isRecording,
            conflict: controller.shortcutConflict,
            onDismissConflict: controller.clearShortcutConflict
        ) { shortcut in
            controller.recordShortcut(shortcut)
        }
    }

    // MARK: Draft a reply

    private var draftReplySection: some View {
        DSSection(
            "Draft replies",
            detail: "Speak an intent to get a drafted reply."
        ) {
            VStack(spacing: 0) {
                DSToggleRow(
                    title: "Draft replies from the conversation",
                    detail: "Hold \(controller.draftShortcut.display) and say what the reply should do — "
                        + "\u{201C}decline politely, suggest Thursday\u{201D}. pluma reads the visible thread and "
                        + "composes the reply at your cursor for you to review. The thread is read once and never stored.",
                    isOn: $controller.draftReplyEnabled,
                    disabled: !controller.isEnabled
                )

                if controller.draftReplyEnabled {
                    DSRowDivider()

                    HStack(spacing: 14) {
                        Text(
                            isRecordingDraft
                                ? "Press and hold the new shortcut. Esc cancels."
                                : "Hold to speak an intent. Uses the same cleanup model below to write the reply."
                        )
                        .font(DS.meta)
                        .foregroundStyle(.secondary)

                        Spacer()

                        ShortcutRecorderView(
                            shortcut: controller.draftShortcut,
                            isRecording: $isRecordingDraft
                        ) { shortcut in
                            controller.recordDraftShortcut(shortcut)
                        }
                    }

                    if !autocomplete.screenContextEnabled
                        || !autocomplete.conversationContextEnabled {
                        DSRowDivider()
                        DSNoticeRow(
                            systemImage: "rectangle.dashed",
                            tint: .orange,
                            text: "Turn on Screen context and Conversation awareness in Settings → Writing so pluma can see the thread. Without them, this shortcut inserts plain dictation."
                        )
                    }
                }
            }
            .dsCard()
        }
    }

    // MARK: Transcription & cleanup

    private var transcriptionSection: some View {
        DSSection(
            "Transcription and cleanup",
            detail: "After you speak, polish and insert.",
            identifier: NavigationFocus.dictationEngines.scrollTarget
        ) {
            VStack(spacing: 0) {
                DSToggleRow(
                    title: "Clean up with AI",
                    detail: "Removes filler words and false starts, fixes punctuation. Keeps your wording; if it fails, the raw transcript is inserted.",
                    isOn: $controller.cleanupEnabled,
                    disabled: !controller.isEnabled
                )

                DSRowDivider()

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(spacing: 0) {
                        DSSettingRow(
                            "Transcribe with",
                            detail: controller.provider.detail
                        ) {
                            Picker("Transcribe with", selection: $controller.provider) {
                                ForEach(DictationProviderChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                            .focused($isEnginePickerFocused)
                        }

                        if controller.cleanupEnabled {
                            DSRowDivider()

                            DSSettingRow("Clean up with") {
                                HStack(spacing: 8) {
                                    Picker("Clean up with", selection: $controller.cleanupProvider) {
                                        ForEach(CleanupProviderChoice.allCases) { choice in
                                            Text(choice.title).tag(choice)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 160)

                                    cleanupModelControl
                                }
                            }
                        }

                        if usesOpenAI {
                            DSRowDivider()
                            openAICredentialRow
                        }
                    }
                    .padding(.top, DS.Spacing.medium)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced")
                            .font(DS.cardBody.weight(.medium))
                        Text(advancedSummary)
                            .font(DS.meta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(DS.Motion.reveal(reduceMotion: reduceMotion), value: showAdvanced)
            .animation(DS.Motion.reveal(reduceMotion: reduceMotion), value: controller.cleanupEnabled)
            .dsCard()
        }
        .id(NavigationFocus.dictationEngines.scrollTarget)
    }

    // MARK: Recipe

    // Always in the same slot as the other feature recipes (after the
    // shortcut). Directives only run when cleanup is on; the cards stay
    // visible so the page layout does not jump.
    private var cleanupRecipeSection: some View {
        DSSection(
            "Recipe",
            detail: controller.cleanupEnabled
                ? "Stack directives to shape the cleanup pass. They apply in order."
                : "Stack directives for the cleanup pass. Turn on Clean up with AI below to use them."
        ) {
            LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                ForEach(CleanupDirective.allCases) { directive in
                    RecipeActionCard(
                        title: directive.title,
                        subtitle: directive.shortDescription,
                        symbolName: directive.symbolName,
                        tint: DS.Feature.dictation.color,
                        eyebrow: "After you speak",
                        stepNumber: controller.cleanupChain
                            .firstIndex(of: directive).map { $0 + 1 }
                    ) {
                        controller.toggleCleanupDirective(directive)
                    }
                }
            }

            if !controller.cleanupChain.isEmpty {
                cleanupStrip
            }
        }
        .disabled(!controller.cleanupEnabled)
        .opacity(controller.cleanupEnabled ? 1 : 0.55)
    }

    private var cleanupStrip: some View {
        DSPipelineStrip(eyebrowTrigger: nil) {
            ForEach(
                Array(controller.cleanupChain.enumerated()), id: \.element
            ) { index, directive in
                if index > 0 {
                    DSPipelineConnector()
                }

                DSPipelineStep(
                    title: directive.title,
                    number: index + 1,
                    tint: DS.Feature.dictation.color,
                    moveLeft: index > 0
                        ? { controller.moveCleanupDirective(directive, offset: -1) }
                        : nil,
                    moveRight: index < controller.cleanupChain.count - 1
                        ? { controller.moveCleanupDirective(directive, offset: 1) }
                        : nil
                ) {
                    controller.removeCleanupDirective(directive)
                }
            }
        }
    }

    @ViewBuilder
    private var cleanupModelControl: some View {
        switch controller.cleanupProvider {
        case .openAI:
            Picker("Model", selection: $controller.openAIModel) {
                ForEach(OpenAIChatModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(width: 140)
        case .ollama:
            if ollamaModels.isEmpty {
                TextField("Ollama model", text: $controller.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            } else {
                Picker("Ollama model", selection: $controller.ollamaModel) {
                    ForEach(ollamaPickerOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
        case .appleOnDevice:
            EmptyView()
        }
    }

    private var openAICredentialRow: some View {
        DSNoticeRow(
            systemImage: credentials.hasKey ? "key.fill" : "key",
            tint: credentialTint,
            text: credentials.state.detail,
            actionTitle: "Manage in AI"
        ) {
            navigation.navigate(
                to: .ai,
                focus: .aiOpenAIKey,
                returningTo: .dictation,
                returnFocus: .dictationEngines
            )
        }
    }

    private var advancedSummary: String {
        var parts = ["Transcribe: \(controller.provider.title)"]
        if controller.cleanupEnabled {
            parts.append("Clean up: \(controller.cleanupProvider.title)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Logic carried from the old card

    private var usesOpenAI: Bool {
        controller.provider == .openAI || controller.cleanupProvider == .openAI
    }

    private var credentialTint: Color {
        switch credentials.state {
        case .ready: .green
        case .invalid, .keychainFailure: .red
        default: .orange
        }
    }

    private var featureScrollTarget: String? {
        guard navigation.focus?.page == .dictation else { return nil }
        return navigation.focus?.scrollTarget
    }

    private func applyNavigationFocus(_ focus: NavigationFocus?) {
        guard focus == .dictationEngines else { return }
        showAdvanced = true
        Task { @MainActor in
            await Task.yield()
            isEnginePickerFocused = true
        }
    }

    // Stated per selection rather than as a blanket claim, because the honest
    // answer changes depending on which two providers are chosen.
    private var privacyNote: String {
        let audio = controller.provider == .openAI
            ? "Microphone audio is sent to \(OpenAIEndpoint.destinationName())."
            : "Speech is transcribed on this Mac; audio never leaves it."
        let text: String
        if !controller.cleanupEnabled {
            text = " Cleanup is off, so the raw transcript is inserted."
        } else if controller.cleanupProvider.isLocal {
            text = " Cleanup runs on this Mac."
        } else {
            text = " The transcript is sent to \(OpenAIEndpoint.destinationName()) for cleanup."
        }
        return audio + text + " If cleanup fails, the raw transcript is inserted instead."
    }

    private var statusColor: Color {
        if controller.isEnabled && !controller.isMicPermitted { return .orange }
        return switch controller.activity {
        case .off: .gray
        case .needsPermission: .orange
        case .preparing: .orange
        case .idle: .green
        case .listening: .red
        case .tidying: .green
        case .unavailable: .orange
        }
    }

    private var statusText: String {
        if controller.isEnabled && !controller.isMicPermitted {
            return "Needs microphone access"
        }
        return switch controller.activity {
        case .off:
            "Dictation is off"
        case .needsPermission:
            "Needs microphone access"
        case .preparing:
            "Preparing the on-device speech model…"
        case .idle:
            "Ready — hold \(controller.shortcut.display) and talk"
        case .listening:
            "Listening…"
        case .tidying:
            "Tidying up your words…"
        case .unavailable(let reason):
            reason
        }
    }

}
