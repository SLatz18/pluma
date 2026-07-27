import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @ObservedObject private var clipboardHotkeys = ClipboardHotkeyManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        TabView {
            Form {
                Section("App") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)

                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Writing model") {
                    Picker("Default model", selection: providerBinding) {
                        ForEach(RewriteProviderChoice.allCases) { provider in
                            Label(provider.title, systemImage: provider.symbolName)
                                .tag(provider)
                        }
                    }

                    if model.provider == .ollama {
                        if model.availableOllamaModels.isEmpty {
                            TextField("Ollama model", text: ollamaModelBinding)
                        } else {
                            Picker("Ollama model", selection: ollamaModelBinding) {
                                ForEach(model.availableOllamaModels, id: \.self) { modelName in
                                    Text(modelName).tag(modelName)
                                }
                            }
                        }
                    }

                    LabeledContent("Status") {
                        Label(model.status.title, systemImage: model.status.symbolName)
                            .foregroundStyle(model.status.isReady ? .green : .secondary)
                    }
                }

                Section("Universal hotkey") {
                    LabeledContent("Reliability") {
                        Label(
                            clipboardHotkeys.status.title,
                            systemImage: clipboardHotkeys.status.symbolName
                        )
                        .foregroundStyle(hotkeyColor)
                    }

                    Text(clipboardHotkeys.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if clipboardHotkeys.status.tier != .enhanced {
                        Button("Enable Enhanced Hotkey…") {
                            clipboardHotkeys.requestInputMonitoringAccess()
                        }
                    }
                }

                Section("Privacy") {
                    Text(
                        model.provider == .appleIntelligence
                            ? "Rewrites run with Apple's on-device model."
                            : "Rewrites are sent only to Ollama at 127.0.0.1."
                    )
                    .foregroundStyle(.secondary)

                    Text(
                        "The universal flow reads your clipboard after you copy. macOS may ask once under Privacy & Security → Paste from Other Apps."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Open Pasteboard Settings…") {
                        PasteboardAccess.openPrivacySettings()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "brain")
                }
        }
        .frame(width: 560, height: 500)
        .task {
            await model.refreshStatus()
            clipboardHotkeys.refresh()
        }
    }

    private var hotkeyColor: Color {
        switch clipboardHotkeys.status.tier {
        case .enhanced: .green
        case .carbonOnly: .orange
        case .unavailable: .red
        }
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

    private var providerBinding: Binding<RewriteProviderChoice> {
        Binding(
            get: { model.provider },
            set: { model.selectProvider($0) }
        )
    }

    private var ollamaModelBinding: Binding<String> {
        Binding(
            get: { model.ollamaModel },
            set: { model.setOllamaModel($0) }
        )
    }
}
