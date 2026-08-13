import AppKit
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case writing
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .writing: "Writing"
        case .privacy: "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gear"
        case .writing: "brain"
        case .privacy: "hand.raised"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @EnvironmentObject private var autocomplete: AutocompleteCoordinator
    @EnvironmentObject private var clipboardRewrite: ClipboardRewriteController
    @EnvironmentObject private var dictation: DictationController
    @EnvironmentObject private var reader: ReaderController
    @EnvironmentObject private var memory: MemoryStore
    @EnvironmentObject private var spellMemory: SpellMemoryStore
    @EnvironmentObject private var styleProfile: StyleProfileStore
    @EnvironmentObject private var developer: DeveloperMode

    @State private var selection: SettingsDestination = .general
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var showImporter = false
    @State private var showStyleEditor = false
    @State private var importError: String?
    @State private var clearTarget: ClearTarget?

    private enum ClearTarget: String, Identifiable {
        case memory
        case spellMemory
        case profile

        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selection) {
            DSSettingsPage {
                generalContent
            }
            .tabItem { Label("General", systemImage: "gear") }
            .tag(SettingsDestination.general)

            DSSettingsPage {
                writingContent
            }
            .tabItem { Label("Writing", systemImage: "brain") }
            .tag(SettingsDestination.writing)

            DSSettingsPage {
                privacyContent
            }
            .tabItem { Label("Privacy", systemImage: "hand.raised") }
            .tag(SettingsDestination.privacy)
        }
        .frame(width: 640, height: 560)
        .task {
            await model.refreshStatus()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false,
            onCompletion: importStyleProfile
        )
        .sheet(isPresented: $showStyleEditor) {
            StyleProfileEditorSheet(store: styleProfile)
        }
        .confirmationDialog(
            clearDialogTitle,
            isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                switch clearTarget {
                case .memory:
                    memory.clear()
                    autocomplete.clearMemory()
                case .spellMemory:
                    spellMemory.clear()
                    autocomplete.clearSpellMemory()
                case .profile:
                    styleProfile.clear()
                case nil:
                    break
                }
                clearTarget = nil
            }
            Button("Cancel", role: .cancel) {
                clearTarget = nil
            }
        } message: {
            Text("This removes the selected local writing data from this Mac and cannot be undone.")
        }
    }

    private var clearDialogTitle: String {
        switch clearTarget {
        case .memory: "Clear all remembered phrases?"
        case .spellMemory: "Clear remembered spelling corrections?"
        case .profile: "Clear the style profile?"
        case nil: "Clear local data?"
        }
    }

    // #47: the clipboard fallback is the path that works in Google Docs and
    // Electron apps, so its state and its permission have to be visible rather
    // than something the writer discovers by pressing a key and seeing nothing.
    private var clipboardFallbackSection: some View {
        DSSection("Clipboard fallback") {
            VStack(spacing: 0) {
                DSToggleRow(
                    title: "Rewrite what I copy",
                    detail: "For apps where selecting text does not work, like Google Docs "
                        + "and Discord. Copy, press \(clipboardRewrite.shortcut.display), then paste.",
                    isOn: Binding(
                        get: { clipboardRewrite.isEnabled },
                        set: { clipboardRewrite.setEnabled($0) }
                    )
                )

                if clipboardRewrite.isEnabled {
                    DSRowDivider()

                    DSSettingRow(
                        "Shortcut",
                        detail: "Press this after copying. Rewrites the clipboard in place."
                    ) {
                        DSBadge(
                            text: clipboardRewrite.shortcut.display,
                            tone: .neutral,
                            systemImage: "keyboard"
                        )
                    }

                    DSRowDivider()

                    DSSettingRow(
                        "Paste from Other Apps",
                        detail: pasteboardPermissionDetail
                    ) {
                        HStack(spacing: DS.Spacing.small) {
                            DSBadge(
                                text: pasteboardPermissionLabel,
                                tone: pasteboardPermissionTone,
                                systemImage: pasteboardPermissionSymbol
                            )
                            Button("Manage…") {
                                PasteboardAccess.openPrivacySettings()
                            }
                        }
                    }

                    if let conflict = clipboardRewrite.shortcutConflict {
                        DSRowDivider()
                        DSNoticeRow(
                            systemImage: "exclamationmark.triangle",
                            tint: .red,
                            text: conflict
                        )
                    }
                }
            }
            .dsCard()
        }
    }

    private var pasteboardPermissionDetail: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny:
            "macOS is blocking clipboard reads, so this shortcut cannot work. "
                + "Allow pluma under Privacy & Security."
        case .alwaysAllow:
            "pluma can read the clipboard without prompting. Reader uses this as a fallback in Google Docs."
        default:
            "macOS may ask once the first time pluma reads your clipboard."
        }
    }

    private var pasteboardPermissionLabel: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: "Denied"
        case .alwaysAllow: "Allowed"
        default: "Asks once"
        }
    }

    private var pasteboardPermissionTone: DS.Tone {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: .attention
        case .alwaysAllow: .success
        default: .neutral
        }
    }

    private var pasteboardPermissionSymbol: String {
        switch PasteboardAccess.accessBehavior {
        case .alwaysDeny: "hand.raised"
        case .alwaysAllow: "checkmark.shield"
        default: "questionmark.circle"
        }
    }

    private var generalContent: some View {
        Group {
            clipboardFallbackSection

            DSSection("App behavior") {
                VStack(spacing: 0) {
                    DSToggleRow(
                        title: "Launch at login",
                        detail: "Keep pluma available from the menu bar after you sign in.",
                        isOn: launchAtLoginBinding
                    )

                    if let launchAtLoginError {
                        DSRowDivider()
                        DSNoticeRow(
                            systemImage: "exclamationmark.triangle",
                            tint: .red,
                            text: launchAtLoginError
                        )
                    }

                    DSRowDivider()

                    DSToggleRow(
                        title: "Developer mode",
                        detail: "Adds the hidden Developer page with diagnostics and component inspection.",
                        isOn: developerModeBinding
                    )
                }
                .dsCard()
            }
        }
        .accessibilityIdentifier("settings-general")
    }

    private var writingContent: some View {
        Group {
            DSSection(
                "Writing model",
                detail: "One shared model choice powers Rewrite and Autocomplete."
            ) {
                VStack(spacing: 0) {
                    DSSettingRow("Default model") {
                        Picker("Default model", selection: providerBinding) {
                            ForEach(RewriteProviderChoice.allCases) { provider in
                                Label(provider.title, systemImage: provider.symbolName)
                                    .tag(provider)
                            }
                        }
                        .labelsHidden()
                        .frame(width: DS.Control.providerWidth)
                    }

                    if model.provider == .ollama {
                        DSRowDivider()
                        DSSettingRow("Ollama model") {
                            ollamaControl
                        }
                    }

                    DSRowDivider()
                    DSStatusIndicator(
                        tone: model.status.isReady ? .success : .attention,
                        text: model.status.title
                    )
                }
                .dsCard()
            }

            DSSection("Context and personalization") {
                VStack(spacing: 0) {
                    DSToggleRow(
                        title: "Screen context",
                        detail: "Read terms near the cursor to improve suggestions and dictation. Screen contents are never stored.",
                        isOn: $autocomplete.screenContextEnabled
                    )
                    DSRowDivider()
                    DSToggleRow(
                        title: "Conversation awareness",
                        detail: "Read the visible conversation thread (Slack, Mail, Messages) to draft replies and keep suggestions on-topic. Uses Accessibility, with the screen as fallback. Read once per request, never stored.",
                        isOn: $autocomplete.conversationContextEnabled,
                        disabled: !autocomplete.screenContextEnabled
                    )
                    DSRowDivider()
                    DSToggleRow(
                        title: "Learn my style",
                        detail: "Store accepted suggestions locally to steer future writing.",
                        isOn: $autocomplete.memoryEnabled
                    )
                }
                .dsCard()
            }

            DSSection("Style profile") {
                VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                    Text(
                        styleProfile.isEmpty
                            ? "Import a plain-text writing guide to steer completions. Frontmatter is removed on import."
                            : "A \(styleProfile.text.count)-character profile guides every completion."
                    )
                    .font(DS.cardBody)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button("Import from File…") { showImporter = true }
                        if !styleProfile.isEmpty {
                            Button("Edit…") { showStyleEditor = true }
                            Button("Clear…", role: .destructive) { clearTarget = .profile }
                        }
                        if let importError {
                            Text(importError)
                                .font(DS.meta)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .dsCard()
            }
        }
        .accessibilityIdentifier("settings-writing")
    }

    private var privacyContent: some View {
        Group {
            DSSection("Processing paths") {
                VStack(spacing: 0) {
                    processingRow(
                        title: "Rewrite and autocomplete",
                        value: model.provider == .appleIntelligence
                            ? "On-device with Apple Intelligence"
                            : "Local loopback through Ollama"
                    )
                    DSRowDivider()
                    processingRow(
                        title: "Dictation audio",
                        value: dictation.provider == .openAI
                            ? "Sent to OpenAI for transcription"
                            : "Transcribed on this Mac"
                    )
                    DSRowDivider()
                    processingRow(
                        title: "Reader",
                        value: reader.speechProvider == .openAI
                            ? "Text sent to OpenAI for speech. Not stored by pluma."
                            : "Spoken on this Mac. Text is not stored."
                    )
                    DSRowDivider()
                    processingRow(
                        title: "Transcript cleanup",
                        value: cleanupPath
                    )
                }
                .dsCard()
            }

            DSSection("Permissions") {
                VStack(spacing: 0) {
                    permissionRow(
                        title: "Accessibility",
                        granted: autocomplete.isPermissionGranted,
                        detail: "Reads focused text fields, speaks or rewrites the selection, and inserts results."
                    ) {
                        autocomplete.requestPermission()
                    }
                    DSRowDivider()
                    permissionRow(
                        title: "Screen Recording",
                        granted: autocomplete.isScreenContextPermitted,
                        detail: "Optional. Reads visible terms when Screen context is on."
                    ) {
                        autocomplete.requestScreenContextPermission()
                    }
                    DSRowDivider()
                    permissionRow(
                        title: "Microphone",
                        granted: dictation.isMicPermitted,
                        detail: "Required only for Dictation."
                    ) {
                        Task { await dictation.requestMicrophonePermission() }
                    }
                }
                .dsCard()
            }

            DSSection("Stored data") {
                VStack(spacing: 0) {
                    dataRow(
                        title: "Style memory",
                        value: "\(memory.count) of 300 phrases",
                        clear: memory.count > 0 ? { clearTarget = .memory } : nil
                    )
                    DSRowDivider()
                    dataRow(
                        title: "Spelling memory",
                        value: "\(spellMemory.count) of \(SpellMemoryStore.maxEntries) corrections",
                        clear: spellMemory.count > 0 ? { clearTarget = .spellMemory } : nil
                    )
                    DSRowDivider()
                    dataRow(
                        title: "Style profile",
                        value: styleProfile.isEmpty
                            ? "Not stored"
                            : "\(styleProfile.text.count) characters",
                        clear: styleProfile.isEmpty ? nil : { clearTarget = .profile }
                    )
                    DSRowDivider()
                    DSSettingRow(
                        "Audio and transcripts",
                        detail: "Never persisted by pluma."
                    ) {
                        DSBadge(text: "Not stored", tone: .success)
                    }
                }
                .dsCard()

                DisclosureGroup("Advanced") {
                    HStack {
                        Button("Reveal style memory in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([memory.url])
                        }
                        Button("Reveal spelling memory") {
                            NSWorkspace.shared.activateFileViewerSelecting([spellMemory.url])
                        }
                        Spacer()
                        Button("Open Diagnostics Log") {
                            NSWorkspace.shared.open(DebugLog.url)
                        }
                    }
                    .padding(.top, DS.Spacing.small)
                }
                .font(DS.meta)
            }
        }
        .accessibilityIdentifier("settings-privacy")
    }

    private func processingRow(title: String, value: String) -> some View {
        DSSettingRow(title) {
            Text(value)
                .font(DS.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        DSSettingRow(title, detail: detail) {
            if granted {
                DSBadge(text: "Granted", tone: .success, systemImage: "checkmark")
            } else {
                Button("Grant…", action: action)
            }
        }
    }

    private func dataRow(
        title: String,
        value: String,
        clear: (() -> Void)?
    ) -> some View {
        DSSettingRow(title) {
            HStack(spacing: DS.Spacing.small) {
                Text(value)
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                if let clear {
                    Button("Clear…", role: .destructive, action: clear)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var ollamaControl: some View {
        if model.availableOllamaModels.isEmpty {
            TextField("Ollama model", text: ollamaModelBinding)
                .frame(width: DS.Control.providerWidth)
        } else {
            Picker("Ollama model", selection: ollamaModelBinding) {
                ForEach(model.availableOllamaModels, id: \.self) { modelName in
                    Text(modelName).tag(modelName)
                }
            }
            .labelsHidden()
            .frame(width: DS.Control.providerWidth)
        }
    }

    private var cleanupPath: String {
        guard dictation.cleanupEnabled else { return "Off; raw transcript is inserted" }
        return dictation.cleanupProvider.isLocal
            ? "Runs on this Mac"
            : "Transcript sent to OpenAI"
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.set(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = "Couldn't update login items: \(error.localizedDescription)"
                }
            }
        )
    }

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { developer.isUnlocked },
            set: { developer.setUnlocked($0) }
        )
    }

    private var providerBinding: Binding<RewriteProviderChoice> {
        Binding(get: { model.provider }, set: { model.selectProvider($0) })
    }

    private var ollamaModelBinding: Binding<String> {
        Binding(get: { model.ollamaModel }, set: { model.setOllamaModel($0) })
    }

    private func importStyleProfile(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try styleProfile.importContents(of: url)
            importError = nil
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct StyleProfileEditorSheet: View {
    let store: StyleProfileStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            Text("Style profile")
                .font(DS.cardTitle)
            Text("Up to \(StyleProfileStore.maxCharacters) characters; longer text is truncated.")
                .font(DS.meta)
                .foregroundStyle(.secondary)

            DSInset {
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
            }

            HStack {
                Text("\(draft.count) characters")
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    store.setText(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DS.pagePadding)
        .frame(width: 540, height: 440)
        .onAppear { draft = store.text }
    }
}
