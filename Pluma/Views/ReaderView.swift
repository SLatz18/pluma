import AVFoundation
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var controller: ReaderController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator

    @State private var isRecording = false
    @State private var playgroundText = ""

    var body: some View {
        DSFeaturePage(
            .reader,
            subtitle: "Select text, press the shortcut, and hear it spoken on this Mac."
        ) {
            heroCard

            shortcutCard

            voiceCard

            playgroundCard

            Text("Speech stays on this Mac. Nothing is stored. Password fields are never read.")
                .font(DS.meta)
                .foregroundStyle(.tertiary)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DSIconTile(systemImage: "speaker.wave.2", tint: DS.Feature.reader.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Listen to the selection")
                        .font(DS.cardTitle)
                    Text("Press the shortcut to start, press it again to stop. If nothing is selected, Reader speaks the clipboard. Escape also stops.")
                        .font(DS.cardBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("Reader", isOn: $controller.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            DSStatusRow(color: statusColor, text: statusText)

            if !autocomplete.isPermissionGranted {
                DSNoticeRow(
                    systemImage: "hand.raised",
                    tint: .orange,
                    text: "Grant Accessibility to read the selection. Without it, Reader speaks whatever is on the clipboard.",
                    actionTitle: "Grant Accessibility Access…"
                ) {
                    autocomplete.requestPermission()
                }
            }
        }
        .dsCard()
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(
                    isRecording
                        ? "Press the new shortcut. Hyperkey chords work too. Esc cancels."
                        : "Press to speak, press again to stop. Hyperkey maps Caps Lock to ⌃⌥⌘, so Caps Lock L works."
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

    private var voiceCard: some View {
        DSSection("Voice") {
            VStack(spacing: 0) {
                DSSettingRow(
                    "Voice",
                    detail: "On-device voices only. The system default follows your Mac’s language."
                ) {
                    Picker("Voice", selection: $controller.voiceIdentifier) {
                        Text("System default").tag("")
                        ForEach(controller.voices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                DSRowDivider()

                DSSettingRow(
                    "Rate",
                    detail: "How quickly the voice reads."
                ) {
                    HStack(spacing: DS.Spacing.small) {
                        Text("Slow")
                            .font(DS.meta)
                            .foregroundStyle(.tertiary)
                        Slider(value: $controller.rate, in: Preferences.readerRateRange)
                            .frame(width: 140)
                        Text("Fast")
                            .font(DS.meta)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .dsCard()
        }
    }

    private var playgroundCard: some View {
        DSSection("Try it here", detail: "Paste a passage and press Read. Your text never leaves this Mac.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        controller.speakPlaygroundText(playgroundText)
                    } label: {
                        if controller.activity == .reading {
                            Label("Stop", systemImage: "stop.fill")
                        } else {
                            Label("Read", systemImage: "speaker.wave.2.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        controller.activity != .reading
                            && playgroundText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                TextEditor(text: $playgroundText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 132)
                    .dsInsetSurface()
                    .disabled(controller.activity == .reading)
            }
            .dsCard()
        }
    }

    private var statusColor: Color {
        switch controller.activity {
        case .off: .gray
        case .idle: .green
        case .reading: .red
        }
    }

    private var statusText: String {
        switch controller.activity {
        case .off:
            "Reader is off"
        case .idle:
            "Ready — press \(controller.shortcut.display) to hear the selection"
        case .reading:
            "Reading…"
        }
    }
}
