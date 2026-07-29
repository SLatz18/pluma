import SwiftUI

struct DictationView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator

    @State private var isRecording = false
    @State private var apiKeyDraft = ""
    @State private var hasKey = OpenAIKey.isPresent
    @State private var ollamaModels: [String] = []

    var body: some View {
        DSPage(
            title: "Dictation",
            subtitle: "Hold the shortcut and talk. Let go, and your words land at the cursor — tidied up.",
            eyebrow: "Hold to talk → typed"
        ) {
            heroCard

            shortcutCard

            transcriptionCard

            VStack(alignment: .leading, spacing: 12) {
                DSEyebrow(trigger: "Context")

                DSToggleRow(
                    title: "Match what's on screen",
                    detail: "Reads names and terms from the frontmost window so they transcribe correctly. Shared with autocomplete.",
                    isOn: $autocomplete.screenContextEnabled
                )
                .dsCard()
            }

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DSIconTile(systemImage: "mic", tint: DS.Feature.dictation.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Push-to-talk, anywhere")
                        .font(DS.cardTitle)
                    Text("Recording runs only while the shortcut is held. Nothing is inserted until you let go, so partial guesses never reach your document.")
                        .font(DS.cardBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("Dictation", isOn: $controller.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            DSStatusRow(color: statusColor, text: statusText)

            if !controller.isMicPermitted {
                DSNoticeRow(
                    systemImage: "mic.slash",
                    tint: .orange,
                    text: "Dictation needs microphone access.",
                    actionTitle: "Grant Microphone Access…"
                ) {
                    Task { await controller.requestMicrophonePermission() }
                }
            }
        }
        .dsCard()
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
            DSEyebrow(trigger: "Transcription & cleanup")

            VStack(spacing: 0) {
                DSToggleRow(
                    title: "Clean up with AI",
                    detail: "Removes filler words and false starts, fixes punctuation. Keeps your wording and meaning; if it fails, the raw transcript is inserted.",
                    isOn: $controller.cleanupEnabled,
                    disabled: !controller.isEnabled
                )

                rowDivider

                HStack(spacing: 8) {
                    Text("Transcribe with")
                        .font(DS.cardBody.weight(.medium))
                    Picker("Transcribe with", selection: $controller.provider) {
                        ForEach(DictationProviderChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)

                    Text(controller.provider.detail)
                        .font(DS.meta)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }

                rowDivider

                HStack(spacing: 8) {
                    Text("Clean up with")
                        .font(DS.cardBody.weight(.medium))
                    Picker("Clean up with", selection: $controller.cleanupProvider) {
                        ForEach(CleanupProviderChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(!controller.cleanupEnabled)

                    switch controller.cleanupProvider {
                    case .openAI:
                        Picker("Model", selection: $controller.openAIModel) {
                            ForEach(OpenAIChatModel.allCases) { model in
                                Text(model.title).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(!controller.cleanupEnabled)
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
                            .disabled(!controller.cleanupEnabled)
                        }
                    case .appleOnDevice:
                        EmptyView()
                    }

                    Spacer()
                }

                if usesOpenAI {
                    rowDivider

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
            }
            .dsCard()
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.vertical, 10)
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
