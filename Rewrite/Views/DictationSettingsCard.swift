import SwiftUI

struct DictationSettingsCard: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var apiKeyDraft = ""
    @State private var isComparing = false
    @State private var hasKey = OpenAIKey.isPresent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "mic")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Dictate anywhere")
                        .font(.headline)
                    Text("Hold the shortcut and talk. Let go and your words land at the cursor, tidied up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("Dictation", isOn: $controller.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()

                    HStack(spacing: 6) {
                        Text("Clean up with AI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("Clean up with AI", isOn: $controller.cleanupEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!controller.isEnabled)
                    }
                }
            }

            HStack(spacing: 14) {
                Text(isRecording ? "…" : controller.shortcut.display)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isRecording ? Color.accentColor : Color.primary.opacity(0.12)
                            )
                    }

                Text(
                    isRecording
                        ? "Press and hold the new shortcut. Esc cancels."
                        : "Hold to talk. Hyperkey maps Caps Lock to ⌃⌥⌘, so Caps Lock R works."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(isRecording ? "Cancel" : "Change…") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .controlSize(.small)
            }

            if !controller.isMicPermitted {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .foregroundStyle(.orange)
                    Text("Dictation needs microphone access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Grant Microphone Access…") {
                        Task { await controller.requestMicrophonePermission() }
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Transcribe with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Transcribe with", selection: $controller.provider) {
                    ForEach(DictationProviderChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 160)

                Text(controller.provider.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Clean up with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Clean up with", selection: $controller.cleanupProvider) {
                    ForEach(CleanupProviderChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(!controller.cleanupEnabled)

                if controller.cleanupProvider == .openAI {
                    Picker("Model", selection: $controller.openAIModel) {
                        ForEach(OpenAIChatModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(!controller.cleanupEnabled)
                }

                Spacer()

                Button("Compare…") { isComparing = true }
                    .controlSize(.small)
                    .disabled(!hasKey)
            }

            if usesOpenAI {
                HStack(spacing: 8) {
                    Image(systemName: hasKey ? "key.fill" : "key")
                        .foregroundStyle(hasKey ? .green : .orange)
                    if hasKey {
                        Text("API key stored in the keychain")
                            .font(.caption)
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
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Match what's on screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Match what's on screen", isOn: $autocomplete.screenContextEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("Reads names and terms from the frontmost window so they transcribe correctly. Shared with autocomplete.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(privacyNote)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .sheet(isPresented: $isComparing) {
            CleanupComparisonView()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var usesOpenAI: Bool {
        controller.provider == .openAI || controller.cleanupProvider == .openAI
    }

    // Stated per selection rather than as a blanket claim, because the honest
    // answer changes depending on which two providers are chosen.
    private var privacyNote: String {
        let audio = controller.provider == .openAI
            ? "Microphone audio is sent to OpenAI."
            : "Speech is transcribed on this Mac; audio never leaves it."
        let text = controller.cleanupEnabled
            ? (
                controller.cleanupProvider == .openAI
                    ? " The transcript is sent to OpenAI for cleanup."
                    : " Cleanup runs on this Mac."
            )
            : " Cleanup is off, so the raw transcript is inserted."
        return audio + text + " If cleanup fails, the raw transcript is inserted instead."
    }

    private var statusColor: Color {
        switch controller.activity {
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
        switch controller.activity {
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

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            if let shortcut = GlobalShortcut(event: event) {
                controller.recordShortcut(shortcut)
                stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
    }
}
