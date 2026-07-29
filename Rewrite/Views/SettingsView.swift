import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RewriteViewModel
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

                Section("Privacy") {
                    Text(
                        model.provider == .appleIntelligence
                            ? "Rewrites run with Apple's on-device model."
                            : "Rewrites are sent only to Ollama at 127.0.0.1."
                    )
                    .foregroundStyle(.secondary)
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
        .frame(width: 560, height: 460)
        .task {
            await model.refreshStatus()
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
