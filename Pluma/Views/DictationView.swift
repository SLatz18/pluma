import SwiftUI

struct DictationView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRecording = false
    @State private var apiKeyDraft = ""
    @State private var hasKey = OpenAIKey.isPresent
    @State private var ollamaModels: [String] = []
    @State private var showAdvanced = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        DSFeaturePage(
            .dictation,
            subtitle: "Hold the shortcut and talk. Release it to insert your words."
        ) {
            heroCard

            shortcutCard

            transcriptionCard

            if controller.cleanupEnabled {
                cleanupRecipeSection
            }

            DSSharedSettingLink(
                title: "Shared screen context",
                value: autocomplete.screenContextEnabled
                    ? "On · improves names and visible terms"
                    : "Off",
                systemImage: "rectangle.dashed.badge.record",
                destination: .writing
            )
            .dsCard()

            Text(privacyNote)
                .font(DS.meta)
                .foregroundStyle(.tertiary)
        }
        .task {
            ollamaModels = (try? await OllamaEngine().availableModels()) ?? []
            if controller.ollamaModel.isEmpty, let first = ollamaModels.first {
                controller.ollamaModel = first
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(
                    isRecording
                        ? "Press and hold the new shortcut. Esc cancels."
                        : "Hold to talk. Hyperkey maps Caps Lock to ⌃⌥⌘, so Caps Lock Space works."
                )
                    .font(DS.meta)
                    .foregroundStyle(.secondary)

                Spacer()

                ShortcutRecorderView(
                    shortcut: controller.shortcut,
                    isRecording: $isRecording
                ) { shortcut in
                    controller.recordShortcut(shortcut)
                }
            }

            if let conflict = controller.shortcutConflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.meta)
                    .foregroundStyle(.orange)
            }
        }
        .dsCard()
    }

    // MARK: Transcription & cleanup

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSEyebrow(trigger: "After you speak", action: "polish and insert")

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
                            apiKeyRow
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
    }

    // MARK: Cleanup recipe

    // Only rendered while AI cleanup is on: with cleanup off the raw
    // transcript is inserted and no directive would ever run.
    private var cleanupRecipeSection: some View {
        DSSection(
            "Cleanup recipe",
            detail: "Stack directives to shape the cleanup pass. They apply in order."
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
    }

    private var cleanupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(
                    Array(controller.cleanupChain.enumerated()), id: \.element
                ) { index, directive in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
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
            .padding(.vertical, 2)
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
                    ForEach(ollamaModels, id: \.self) { name in
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

    private var apiKeyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: hasKey ? "key.fill" : "key")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasKey ? .green : .orange)
                .frame(width: 18)
            if hasKey {
                Text("API key stored in the keychain")
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    OpenAIKey.clear()
                    hasKey = false
                    apiKeyDraft = ""
                    Task { await controller.prepare() }
                }
                .controlSize(.small)
            } else {
                SecureField("OpenAI API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("Save") {
                    OpenAIKey.save(apiKeyDraft)
                    hasKey = OpenAIKey.isPresent
                    apiKeyDraft = ""
                    Task { await controller.prepare() }
                }
                .controlSize(.small)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
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

    // Stated per selection rather than as a blanket claim, because the honest
    // answer changes depending on which two providers are chosen.
    private var privacyNote: String {
        let audio = controller.provider == .openAI
            ? "Microphone audio is sent to OpenAI."
            : "Speech is transcribed on this Mac; audio never leaves it."
        let text: String
        if !controller.cleanupEnabled {
            text = " Cleanup is off, so the raw transcript is inserted."
        } else if controller.cleanupProvider.isLocal {
            text = " Cleanup runs on this Mac."
        } else {
            text = " The transcript is sent to OpenAI for cleanup."
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
