import SwiftUI

struct DictationSettingsCard: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator

    @State private var isRecording = false
    @State private var keyMonitor: Any?

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
                        : "Hold to talk. Caps Lock counts as ⌃⌥⇧⌘, so Caps Lock R works."
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

            Text("Speech is transcribed by the on-device model; audio never leaves this Mac and is not saved. Cleanup uses your selected writing model. If cleanup fails, the raw transcript is inserted instead.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onDisappear {
            stopRecording()
        }
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
