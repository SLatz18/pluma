import SwiftUI

/// The editable control center for choices that determine which AI service a
/// feature calls. Every picker binds to the owning feature controller; this
/// view does not mirror selections into local state.
struct AISettingsContent: View {
    @EnvironmentObject private var model: RewriteViewModel
    @EnvironmentObject private var dictation: DictationController
    @EnvironmentObject private var reader: ReaderController
    @EnvironmentObject private var credentials: OpenAICredentials
    @EnvironmentObject private var customTTS: CustomTTSCredentials

    @ObservedObject private var navigation = MainNavigation.shared
    @State private var keyDraft = ""
    @State private var isReplacingKey = false
    @State private var customKeyDraft = ""
    @State private var isReplacingCustomKey = false
    @FocusState private var isKeyFieldFocused: Bool

    var body: some View {
        Group {
            openAIAccessSection
            writingSection
            dictationSection
            readerSection
            if reader.speechProvider == .customOpenAICompatible {
                customEndpointSection
            }
        }
        .task {
            await model.refreshStatus()
            if credentials.state.needsValidation {
                await credentials.validate()
            }
        }
        .onAppear { applyNavigationFocus(navigation.focus) }
        .onChange(of: navigation.focus) { _, focus in
            applyNavigationFocus(focus)
        }
    }

    private var openAIAccessSection: some View {
        DSSection(
            "OpenAI access",
            detail: "One Keychain credential is shared by OpenAI transcription, cleanup, and speech. pluma never displays it again.",
            identifier: NavigationFocus.aiOpenAIKey.scrollTarget
        ) {
            VStack(spacing: 0) {
                DSSettingRow("API key", detail: credentials.state.detail) {
                    if credentials.state == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    DSBadge(
                        text: credentials.state.title,
                        tone: credentialTone,
                        systemImage: credentialSymbol
                    )
                }

                DSRowDivider()

                if credentials.hasKey, !isReplacingKey {
                    HStack(spacing: DS.Spacing.small) {
                        Button("Replace…") {
                            isReplacingKey = true
                            focusKeyField()
                        }
                        Button("Check") {
                            Task { await checkCredentialAndRefreshDependents() }
                        }
                        .disabled(credentials.state == .checking)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            credentials.remove()
                            keyDraft = ""
                            refreshCredentialDependents()
                        }
                    }
                } else {
                    HStack(spacing: DS.Spacing.small) {
                        SecureField("OpenAI API key", text: $keyDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeyFieldFocused)
                            .accessibilityIdentifier("ai-openai-key")
                        Button("Save") {
                            Task { await saveCredential() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || credentials.state == .checking
                        )
                        if credentials.hasKey {
                            Button("Cancel") {
                                keyDraft = ""
                                isReplacingKey = false
                            }
                        }
                    }
                }

                DSRowDivider()

                DSSettingRow("Stored in") {
                    DSBadge(text: "macOS Keychain", tone: .success, systemImage: "lock.fill")
                }
            }
            .dsCard()
        }
        .id(NavigationFocus.aiOpenAIKey.scrollTarget)
    }

    private var writingSection: some View {
        DSSection(
            "Writing and Reader summaries",
            detail: "Rewrite, Autocomplete, and Reader summaries share this engine. OpenAI is not offered here because pluma has no OpenAI writing provider.",
            identifier: NavigationFocus.aiWriting.scrollTarget
        ) {
            VStack(spacing: 0) {
                DSSettingRow("Engine") {
                    Picker("Writing engine", selection: writingProviderBinding) {
                        ForEach(RewriteProviderChoice.allCases) { provider in
                            Label(provider.title, systemImage: provider.symbolName)
                                .tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: DS.Control.providerWidth)
                    .accessibilityIdentifier("ai-writing-engine")
                }

                if model.provider == .ollama {
                    DSRowDivider()
                    DSSettingRow("Model") {
                        if model.availableOllamaModels.isEmpty {
                            TextField("Ollama model", text: writingOllamaModelBinding)
                                .frame(width: DS.Control.providerWidth)
                        } else {
                            Picker("Ollama model", selection: writingOllamaModelBinding) {
                                ForEach(model.availableOllamaModels, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: DS.Control.providerWidth)
                        }
                    }
                }

                DSRowDivider()
                DSSettingRow("Data path") {
                    dataPathBadge(
                        text: model.provider == .appleIntelligence ? "On device" : "Local loopback",
                        isCloud: false
                    )
                }

                DSRowDivider()
                DSStatusIndicator(
                    tone: model.status.isReady ? .success : .attention,
                    text: model.status.title
                )

                DSRowDivider()
                DSSettingRow("Open feature") {
                    HStack(spacing: DS.Spacing.small) {
                        Button("Rewrite") {
                            openFeature(.rewrite, focus: .rewriteModel, returnFocus: .aiWriting)
                        }
                        Button("Reader recipe") {
                            openFeature(.reader, focus: .readerRecipe, returnFocus: .aiWriting)
                        }
                    }
                }
            }
            .dsCard()
        }
        .id(NavigationFocus.aiWriting.scrollTarget)
    }

    private var dictationSection: some View {
        DSSection(
            "Dictation",
            detail: "Transcription and post-transcription cleanup are separate choices.",
            identifier: NavigationFocus.aiDictation.scrollTarget
        ) {
            VStack(spacing: 0) {
                subsectionLabel("Transcription")
                DSRowDivider()
                DSSettingRow("Engine", detail: dictation.provider.detail) {
                    Picker("Transcription engine", selection: $dictation.provider) {
                        ForEach(DictationProviderChoice.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: DS.Control.providerWidth)
                    .accessibilityIdentifier("ai-dictation-transcription-engine")
                }

                DSRowDivider()
                DSSettingRow("Model", detail: "Fixed until pluma supports another transcription model.") {
                    DSBadge(
                        text: dictation.provider == .openAI
                            ? "gpt-live-transcribe"
                            : "Apple Speech",
                        systemImage: "waveform"
                    )
                }

                DSRowDivider()
                DSSettingRow("Data path") {
                    dataPathBadge(
                        text: dictation.provider == .openAI ? "Audio to OpenAI" : "On device",
                        isCloud: dictation.provider == .openAI
                    )
                }

                DSRowDivider()
                subsectionLabel("Cleanup and draft replies")
                DSRowDivider()
                DSSettingRow("Engine", detail: dictation.cleanupProvider.detail) {
                    Picker("Cleanup engine", selection: $dictation.cleanupProvider) {
                        ForEach(CleanupProviderChoice.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: DS.Control.providerWidth)
                    .accessibilityIdentifier("ai-dictation-cleanup-engine")
                }

                if dictation.cleanupProvider != .appleOnDevice {
                    DSRowDivider()
                    DSSettingRow("Model") {
                        cleanupModelControl
                    }
                }

                DSRowDivider()
                DSSettingRow("Data path") {
                    dataPathBadge(
                        text: dictation.cleanupProvider == .openAI
                            ? "Text to OpenAI"
                            : dictation.cleanupProvider == .ollama ? "Local loopback" : "On device",
                        isCloud: dictation.cleanupProvider == .openAI
                    )
                }

                DSRowDivider()
                DSSettingRow("Open feature") {
                    Button("Dictation") {
                        openFeature(
                            .dictation,
                            focus: .dictationEngines,
                            returnFocus: .aiDictation
                        )
                    }
                    .accessibilityIdentifier("ai-open-dictation")
                }
            }
            .dsCard()
        }
        .id(NavigationFocus.aiDictation.scrollTarget)
    }

    private var readerSection: some View {
        DSSection(
            "Reader speech",
            detail: "Reader’s summary engine is above; these controls choose how the final text is spoken.",
            identifier: NavigationFocus.aiReader.scrollTarget
        ) {
            VStack(spacing: 0) {
                DSSettingRow("Engine", detail: reader.speechProvider.detail) {
                    Picker("Speech engine", selection: $reader.speechProvider) {
                        ForEach(ReaderSpeechProviderChoice.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: DS.Control.providerWidth)
                    .accessibilityIdentifier("ai-reader-speech-engine")
                }

                DSRowDivider()
                DSSettingRow("Voice") {
                    readerVoiceControl
                }

                if reader.speechProvider == .openAI {
                    DSRowDivider()
                    DSSettingRow("Model", detail: reader.selectedOpenAIModelDetail) {
                        Picker("OpenAI TTS model", selection: $reader.openAITTSModelID) {
                            ForEach(reader.openAIModels) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }

                if reader.speechProvider == .customOpenAICompatible {
                    DSRowDivider()
                    DSSettingRow("Model", detail: reader.selectedCustomModelDetail) {
                        Picker("Custom TTS model", selection: $reader.customTTSModelID) {
                            ForEach(reader.customModelOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("ai-custom-tts-model")
                    }
                }

                DSRowDivider()
                DSSettingRow("Data path") {
                    dataPathBadge(
                        text: readerDataPathText,
                        isCloud: !reader.speechProvider.isLocal
                    )
                }

                DSRowDivider()
                DSSettingRow("Preview voice", detail: "Speaks a fixed sample without reading another app.") {
                    Button(reader.isSpeaking ? "Stop" : "Preview") {
                        if reader.isSpeaking {
                            reader.stopSpeaking()
                        } else {
                            reader.previewVoice()
                        }
                    }
                    .disabled(
                        (reader.speechProvider == .openAI && !credentials.hasKey)
                            || (reader.speechProvider == .customOpenAICompatible && !customTTS.isReady)
                    )
                    .accessibilityIdentifier("ai-preview-reader-voice")
                }

                if reader.speechProvider == .openAI,
                   let status = reader.openAICatalogStatus {
                    DSRowDivider()
                    DSStatusIndicator(
                        tone: credentials.hasKey ? .neutral : .attention,
                        text: status
                    )
                }

                if reader.speechProvider == .customOpenAICompatible,
                   let status = reader.customCatalogStatus {
                    DSRowDivider()
                    DSStatusIndicator(
                        tone: customTTS.isReady ? .neutral : .attention,
                        text: status
                    )
                }

                DSRowDivider()
                DSSettingRow("Open feature") {
                    Button("Reader") {
                        openFeature(.reader, focus: .readerSpeech, returnFocus: .aiReader)
                    }
                    .accessibilityIdentifier("ai-open-reader")
                }
            }
            .dsCard()
        }
        .id(NavigationFocus.aiReader.scrollTarget)
    }

    private var customEndpointSection: some View {
        DSSection(
            "Custom endpoint",
            detail: "An OpenAI-compatible service you run or trust. Reader sends only the text being spoken, with the key below."
        ) {
            VStack(spacing: 0) {
                DSSettingRow(
                    "Base URL",
                    detail: "Usually ends in /v1. pluma appends /audio/speech."
                ) {
                    HStack(spacing: DS.Spacing.small) {
                        if !customTTS.isBaseURLValid, !customTTS.baseURLString.isEmpty {
                            DSBadge(text: "Needs https", tone: .attention, systemImage: "exclamationmark.triangle")
                        }
                        TextField("https://example.com/openai/v1", text: $customTTS.baseURLString)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                            .accessibilityIdentifier("ai-custom-tts-base-url")
                    }
                }

                DSRowDivider()

                if customTTS.hasKey, !isReplacingCustomKey {
                    HStack(spacing: DS.Spacing.small) {
                        Button("Replace…") { isReplacingCustomKey = true }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            customTTS.removeKey()
                            customKeyDraft = ""
                        }
                    }
                } else {
                    HStack(spacing: DS.Spacing.small) {
                        SecureField("Endpoint API key", text: $customKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("ai-custom-tts-key")
                        Button("Save") {
                            customTTS.save(key: customKeyDraft)
                            customKeyDraft = ""
                            isReplacingCustomKey = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if customTTS.hasKey {
                            Button("Cancel") {
                                customKeyDraft = ""
                                isReplacingCustomKey = false
                            }
                        }
                    }
                }

                DSRowDivider()

                DSSettingRow("Stored in") {
                    DSBadge(text: "macOS Keychain", tone: .success, systemImage: "lock.fill")
                }

                if let age = customKeyAgeDays {
                    DSRowDivider()
                    DSStatusIndicator(
                        tone: age >= 28 ? .attention : .neutral,
                        text: age >= 28
                            ? "Key saved \(age) days ago — endpoints that rotate keys may reject it now."
                            : "Key saved \(age == 0 ? "today" : "\(age) days ago")."
                    )
                }
            }
            .dsCard()
        }
    }

    private var customKeyAgeDays: Int? {
        guard customTTS.hasKey, let savedAt = customTTS.keySavedAt else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: savedAt, to: Date()).day ?? 0)
    }

    private var writingProviderBinding: Binding<RewriteProviderChoice> {
        Binding(get: { model.provider }, set: { model.selectProvider($0) })
    }

    private var writingOllamaModelBinding: Binding<String> {
        Binding(get: { model.ollamaModel }, set: { model.setOllamaModel($0) })
    }

    @ViewBuilder
    private var cleanupModelControl: some View {
        switch dictation.cleanupProvider {
        case .appleOnDevice:
            EmptyView()
        case .ollama:
            TextField("Ollama model", text: $dictation.ollamaModel)
                .textFieldStyle(.roundedBorder)
                .frame(width: DS.Control.providerWidth)
        case .openAI:
            Picker("OpenAI cleanup model", selection: $dictation.openAIModel) {
                ForEach(OpenAIChatModel.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: DS.Control.providerWidth)
        }
    }

    @ViewBuilder
    private var readerVoiceControl: some View {
        switch reader.speechProvider {
        case .appleOnDevice:
            Picker("Apple voice", selection: $reader.voiceIdentifier) {
                Text("System default").tag("")
                ForEach(reader.voiceSections, id: \.tier) { section in
                    Section(section.title) {
                        ForEach(section.voices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 220)
        case .openAI:
            Picker("OpenAI voice", selection: $reader.openAIVoiceID) {
                ForEach(reader.openAIVoiceOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: DS.Control.providerWidth)
        case .customOpenAICompatible:
            Picker("Custom voice", selection: $reader.customTTSVoiceID) {
                ForEach(reader.customVoiceOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: DS.Control.providerWidth)
            .accessibilityIdentifier("ai-custom-tts-voice")
        }
    }

    private var readerDataPathText: String {
        switch reader.speechProvider {
        case .appleOnDevice: "On device"
        case .openAI: "Text to OpenAI"
        case .customOpenAICompatible: "Text to your endpoint"
        }
    }

    private func subsectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(DS.meta.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func dataPathBadge(text: String, isCloud: Bool) -> some View {
        DSBadge(
            text: text,
            tone: isCloud ? .attention : .success,
            systemImage: isCloud ? "cloud" : "lock.shield"
        )
    }

    private var credentialTone: DS.Tone {
        switch credentials.state {
        case .ready: .success
        case .missing, .stored, .checking, .offline, .unavailable: .attention
        case .invalid, .keychainFailure: .failure
        }
    }

    private var credentialSymbol: String {
        switch credentials.state {
        case .ready: "checkmark.seal.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .invalid, .keychainFailure: "exclamationmark.triangle.fill"
        case .offline, .unavailable: "wifi.exclamationmark"
        case .missing, .stored: "key"
        }
    }

    private func saveCredential() async {
        await credentials.save(keyDraft)
        if credentials.hasKey {
            keyDraft = ""
            isReplacingKey = false
        }
        refreshCredentialDependents()
    }

    private func checkCredentialAndRefreshDependents() async {
        await credentials.validate()
        refreshCredentialDependents()
    }

    private func refreshCredentialDependents() {
        Task { await dictation.prepare() }
        reader.refreshOpenAITTSCatalog()
    }

    private func openFeature(
        _ page: MainPage,
        focus: NavigationFocus?,
        returnFocus: NavigationFocus
    ) {
        navigation.navigate(
            to: page,
            focus: focus,
            returningTo: .ai,
            returnFocus: returnFocus
        )
    }

    private func applyNavigationFocus(_ focus: NavigationFocus?) {
        guard focus == .aiOpenAIKey else { return }
        if credentials.hasKey {
            isReplacingKey = true
        }
        focusKeyField()
    }

    private func focusKeyField() {
        Task { @MainActor in
            await Task.yield()
            isKeyFieldFocused = true
        }
    }
}
