import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RewriteViewModel

    var body: some View {
        Form {
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

            Section("Style profile") {
                Picker("Profile", selection: profileBinding) {
                    ForEach(model.availableProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                let profile = model.selectedProfile
                if profile.id != StyleProfile.none.id {
                    Text(profile.summary)
                        .foregroundStyle(.secondary)
                    if !profile.bannedPhrases.isEmpty {
                        Text("Avoids: \(profile.bannedPhrases.prefix(3).joined(separator: ", "))\(profile.bannedPhrases.count > 3 ? ", \u{2026}" : "")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if profile.isManaged {
                        Label("Managed by your organization", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Custom profiles: drop JSON files in ~/Library/Application Support/Rewrite/StyleProfiles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .frame(width: 480, height: 380)
        .task {
            await model.refreshStatus()
        }
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

    private var profileBinding: Binding<String> {
        Binding(
            get: { model.selectedProfileID },
            set: { model.selectProfile($0) }
        )
    }
}
