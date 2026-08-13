import AVFoundation
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var controller: ReaderController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var model: RewriteViewModel

    @State private var isRecording = false
    @State private var playgroundText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        DSFeaturePage(
            flowDefinition,
            subtitle: "Read selected text as written, or turn it into a concise spoken summary."
        ) {
            heroCard

            shortcutCard

            listeningRecipeSection

            voiceCard

            playgroundCard

            DSPageFootnote(text: privacyText)
        }
    }

    private var heroCard: some View {
        DSFeatureHero(
            systemImage: "speaker.wave.2",
            tint: DS.Feature.reader.color,
            title: "Listen to the selection",
            detail: "Press the shortcut to start, press it again to stop. Reader captures the live selection in TextEdit, Google Docs, and other apps. Escape also stops.",
            isOn: $controller.isEnabled,
            toggleLabel: "Reader",
            statusColor: statusColor,
            statusText: statusText,
            notice: autocomplete.isPermissionGranted ? nil : DSNoticeRow(
                systemImage: "hand.raised",
                tint: .orange,
                text: "Grant Accessibility to read selected text. Reader will not substitute unrelated clipboard text when access is missing.",
                actionTitle: "Grant Accessibility Access…"
            ) {
                autocomplete.requestPermission()
            }
        )
    }

    private var listeningRecipeSection: some View {
        DSSection(
            "Recipe",
            detail: "Choose how Reader prepares the selection before speaking."
        ) {
            LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                ForEach(ReaderDeliveryMode.allCases) { mode in
                    RecipeActionCard(
                        title: mode.title,
                        subtitle: mode.shortDescription,
                        symbolName: mode.symbolName,
                        tint: DS.Feature.reader.color,
                        eyebrow: "Before speaking",
                        stepNumber: controller.deliveryMode == mode ? 1 : nil,
                        selectionBehavior: .exclusiveChoice
                    ) {
                        controller.deliveryMode = mode
                    }
                }
            }

            listeningPipelineStrip

            if controller.deliveryMode == .summarizeWhenHelpful {
                DSSharedSettingLink(
                    title: "Summary model",
                    value: model.provider.title,
                    systemImage: model.provider.symbolName,
                    destination: .writing
                )
                .dsCard()
            }
        }
    }

    private var listeningPipelineStrip: some View {
        DSPipelineStrip {
            DSBadge(
                text: controller.shortcut.display,
                tone: .neutral,
                systemImage: "keyboard"
            )

            DSPipelineConnector()

            DSPipelineStep(
                title: controller.deliveryMode.title,
                number: 1,
                tint: DS.Feature.reader.color
            )

            DSPipelineConnector()

            DSBadge(
                text: "Read aloud",
                tone: .neutral,
                systemImage: "speaker.wave.2.fill"
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var shortcutCard: some View {
        DSShortcutCard(
            systemImage: "keyboard",
            title: "Press to speak",
            detail: isRecording
                ? "Press the new shortcut. Caps Lock chords work too. Esc cancels."
                : "Press again to stop. Caps Lock L works when Caps shortcuts are on in Settings.",
            shortcut: controller.shortcut,
            isRecording: $isRecording,
            conflict: controller.shortcutConflict
        ) { shortcut in
            controller.recordShortcut(shortcut)
        }
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
        DSSection("Try it here", detail: playgroundDetail) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        Task { await controller.speakPlaygroundText(playgroundText) }
                    } label: {
                        if controller.activity == .processing || controller.activity == .reading {
                            Label("Stop", systemImage: "stop.fill")
                        } else {
                            Label(controller.deliveryMode.shortTitle, systemImage: "speaker.wave.2.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        controller.activity != .processing
                            && controller.activity != .reading
                            && playgroundText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                TextEditor(text: $playgroundText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 132)
                    .dsInsetSurface()
                    .disabled(controller.activity == .processing || controller.activity == .reading)
            }
            .dsCard()
        }
    }

    private var statusColor: Color {
        switch controller.activity {
        case .off: .gray
        case .idle:
            if !autocomplete.isPermissionGranted || controller.errorMessage != nil {
                .orange
            } else {
                .green
            }
        case .processing: .orange
        case .reading: .red
        }
    }

    private var statusText: String {
        switch controller.activity {
        case .off:
            "Reader is off"
        case .idle:
            if !autocomplete.isPermissionGranted {
                "Needs Accessibility access to read the selection"
            } else if let error = controller.errorMessage {
                "Couldn’t summarize: \(error)"
            } else {
                "Ready — press \(controller.shortcut.display) to hear the selection"
            }
        case .processing:
            "Summarizing for listening…"
        case .reading:
            "Reading…"
        }
    }

    private var flowDefinition: FeatureDefinition {
        guard controller.deliveryMode == .summarizeWhenHelpful else { return .reader }
        return FeatureDefinition(
            id: .reader,
            name: "Reader",
            symbolName: "speaker.wave.2",
            tint: .reader,
            trigger: "Select text and press the shortcut",
            action: "Summarize when helpful",
            result: "Speak the summary on this Mac",
            enabledStatus: "Ready to summarize and read selected text",
            disabledStatus: "Reader is off"
        )
    }

    private var playgroundDetail: String {
        switch controller.deliveryMode {
        case .verbatim:
            "Paste a passage and press Read. Speech stays on this Mac."
        case .summarizeWhenHelpful:
            "Paste a passage to run it through \(model.provider.title), then hear the result."
        }
    }

    private var privacyText: String {
        switch controller.deliveryMode {
        case .verbatim:
            "Speech stays on this Mac. Nothing is stored. Password fields are never read."
        case .summarizeWhenHelpful:
            "Summaries use \(model.provider.title); speech uses Apple’s on-device voices. Nothing is stored. Password fields are never read."
        }
    }
}
