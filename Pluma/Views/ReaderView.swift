import AVFoundation
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var controller: ReaderController
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var model: RewriteViewModel

    @State private var isRecording = false
    @State private var playgroundText = ""
    @State private var hasOpenAIKey = OpenAIKey.isPresent
    @State private var apiKeyDraft = ""

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

            speechProviderSection

            voiceCard

            playgroundCard

            Text(privacyText)
                .font(DS.meta)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            hasOpenAIKey = OpenAIKey.isPresent
            controller.refreshInstalledVoices()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DSIconTile(systemImage: "speaker.wave.2", tint: DS.Feature.reader.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Listen to the selection")
                        .font(DS.cardTitle)
                    Text("Press the shortcut to start, press it again to stop. Reader captures the live selection in TextEdit, Google Docs, and other apps. Escape also stops.")
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
                    text: "Grant Accessibility to read selected text. Reader will not substitute unrelated clipboard text when access is missing.",
                    actionTitle: "Grant Accessibility Access…"
                ) {
                    autocomplete.requestPermission()
                }
            }
        }
        .dsCard()
    }

    private var listeningRecipeSection: some View {
        DSSection(
            "Listening recipe",
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
        VStack(alignment: .leading, spacing: 12) {
            DSEyebrow(trigger: "Your pipeline", action: "runs left to right")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    DSBadge(
                        text: controller.shortcut.display,
                        tone: .neutral,
                        systemImage: "keyboard"
                    )

                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)

                    DSPipelineStep(
                        title: controller.deliveryMode.title,
                        number: 1,
                        tint: DS.Feature.reader.color
                    )

                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)

                    DSBadge(
                        text: controller.speechProvider.title,
                        tone: .neutral,
                        systemImage: controller.speechProvider.symbolName
                    )
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
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

    private var speechProviderSection: some View {
        DSSection(
            "Speech",
            detail: "Choose the voice engine. Apple stays on this Mac; OpenAI sends text for synthesis."
        ) {
            LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                ForEach(ReaderSpeechProviderChoice.allCases) { provider in
                    RecipeActionCard(
                        title: provider.title,
                        subtitle: provider.detail,
                        symbolName: provider.symbolName,
                        tint: DS.Feature.reader.color,
                        eyebrow: "Voice engine",
                        stepNumber: controller.speechProvider == provider ? 1 : nil,
                        selectionBehavior: .exclusiveChoice
                    ) {
                        controller.speechProvider = provider
                        hasOpenAIKey = OpenAIKey.isPresent
                    }
                }
            }
        }
    }

    private var voiceCard: some View {
        DSSection("Voice") {
            VStack(spacing: 0) {
                switch controller.speechProvider {
                case .appleOnDevice:
                    appleVoiceControls
                case .openAI:
                    openAIVoiceControls
                }

                DSRowDivider()

                DSSettingRow(
                    "Rate",
                    detail: controller.speechProvider == .openAI
                        ? "Mapped to OpenAI playback speed."
                        : "How quickly the voice reads."
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

    @ViewBuilder
    private var appleVoiceControls: some View {
        DSSettingRow(
            "Voice",
            detail: "Premium and Enhanced voices sound more natural. Download them in Spoken Content."
        ) {
            Picker("Voice", selection: $controller.voiceIdentifier) {
                Text("System default").tag("")
                ForEach(controller.voiceSections, id: \.tier) { section in
                    Section(section.title) {
                        ForEach(section.voices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 220)
        }

        DSRowDivider()

        VStack(alignment: .leading, spacing: 10) {
            if controller.hasPremiumAppleVoices {
                DSNoticeRow(
                    systemImage: "checkmark.seal",
                    tint: .green,
                    text: "Premium Apple voices are installed. Manage downloads in Spoken Content.",
                    actionTitle: "Open Spoken Content…"
                ) {
                    SpokenContentSettings.open()
                }
            } else {
                DSNoticeRow(
                    systemImage: "arrow.down.circle",
                    tint: .orange,
                    text: "For clearer speech, download Premium voices in System Settings → Accessibility → Spoken Content.",
                    actionTitle: "Open Spoken Content…"
                ) {
                    SpokenContentSettings.open()
                }
            }

            HStack(spacing: 8) {
                Button("Refresh voice list") {
                    controller.refreshInstalledVoices()
                }
                .controlSize(.small)

                if !controller.hasPremiumAppleVoices {
                    Button("Use best installed") {
                        controller.refreshInstalledVoices()
                        let preferred = ReaderVoiceCatalog.preferredIdentifier(
                            in: controller.voiceEntries
                        )
                        if !preferred.isEmpty {
                            controller.voiceIdentifier = preferred
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var openAIVoiceControls: some View {
        DSSettingRow(
            "Voice",
            detail: "OpenAI neural voices. Text is sent for synthesis, then played locally."
        ) {
            Picker("OpenAI voice", selection: $controller.openAIVoice) {
                ForEach(OpenAITTSVoice.allCases) { voice in
                    Text(voice.title).tag(voice)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }

        DSRowDivider()

        DSSettingRow(
            "Model",
            detail: controller.openAITTSModel.detail
        ) {
            Picker("OpenAI TTS model", selection: $controller.openAITTSModel) {
                ForEach(OpenAITTSModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }

        DSRowDivider()

        apiKeyRow
            .padding(.vertical, 8)
    }

    private var apiKeyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: hasOpenAIKey ? "key.fill" : "key")
                .font(DS.cardBody.weight(.semibold))
                .foregroundStyle(hasOpenAIKey ? .green : .orange)
                .frame(width: 18)
            if hasOpenAIKey {
                Text("API key stored in the keychain")
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    OpenAIKey.clear()
                    hasOpenAIKey = false
                    apiKeyDraft = ""
                }
                .controlSize(.small)
            } else {
                SecureField("OpenAI API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button("Save") {
                    OpenAIKey.save(apiKeyDraft)
                    hasOpenAIKey = OpenAIKey.isPresent
                    apiKeyDraft = ""
                }
                .controlSize(.small)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
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
            if !autocomplete.isPermissionGranted
                || controller.errorMessage != nil
                || (controller.speechProvider == .openAI && !hasOpenAIKey) {
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
            } else if controller.speechProvider == .openAI && !hasOpenAIKey {
                "Add an OpenAI API key to speak with OpenAI"
            } else if let error = controller.errorMessage {
                "Couldn’t speak: \(error)"
            } else {
                "Ready — press \(controller.shortcut.display) to hear the selection"
            }
        case .processing:
            "Summarizing for listening…"
        case .reading:
            controller.speechProvider == .openAI ? "Preparing or reading…" : "Reading…"
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
            result: controller.speechProvider.isLocal
                ? "Speak the summary on this Mac"
                : "Speak the summary with OpenAI",
            enabledStatus: "Ready to summarize and read selected text",
            disabledStatus: "Reader is off"
        )
    }

    private var playgroundDetail: String {
        switch (controller.deliveryMode, controller.speechProvider) {
        case (.verbatim, .appleOnDevice):
            "Paste a passage and press Read. Speech stays on this Mac."
        case (.verbatim, .openAI):
            "Paste a passage and press Read. Text is sent to OpenAI for speech."
        case (.summarizeWhenHelpful, .appleOnDevice):
            "Paste a passage to run it through \(model.provider.title), then hear it on this Mac."
        case (.summarizeWhenHelpful, .openAI):
            "Paste a passage to summarize with \(model.provider.title), then speak with OpenAI."
        }
    }

    private var privacyText: String {
        let speech: String
        switch controller.speechProvider {
        case .appleOnDevice:
            speech = "Speech uses Apple’s on-device voices."
        case .openAI:
            speech = "Speech sends text to OpenAI for synthesis."
        }
        switch controller.deliveryMode {
        case .verbatim:
            return "\(speech) Nothing is stored. Password fields are never read."
        case .summarizeWhenHelpful:
            return "Summaries use \(model.provider.title). \(speech) Nothing is stored. Password fields are never read."
        }
    }
}
