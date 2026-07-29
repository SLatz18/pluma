import AppKit
import Foundation

@MainActor
final class RewriteViewModel: ObservableObject {
    @Published private(set) var provider: RewriteProviderChoice
    @Published private(set) var selectedIntent: RewriteIntent
    @Published private(set) var status: ProviderStatus = .checking
    @Published var inputText = "yo idk if u c the deck but ngl the numbers r kinda mid rn, lmk if u want me 2 fix em up b4 the meeting tmrw fr fr"
    @Published var outputText = ""
    @Published var ollamaModel: String
    @Published private(set) var availableOllamaModels: [String] = []
    @Published private(set) var isRewriting = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = Preferences.provider(from: defaults)
        selectedIntent = Preferences.intent(from: defaults)
        ollamaModel = Preferences.ollamaModel(from: defaults)
    }

    func selectProvider(_ newProvider: RewriteProviderChoice) {
        provider = newProvider
        defaults.set(newProvider.rawValue, forKey: Preferences.providerKey)
        Task { await refreshStatus() }
    }

    func selectIntent(_ newIntent: RewriteIntent) {
        selectedIntent = newIntent
        defaults.set(newIntent.rawValue, forKey: Preferences.intentKey)
        outputText = ""
        errorMessage = nil
    }

    func setOllamaModel(_ model: String) {
        ollamaModel = model
        defaults.set(model, forKey: Preferences.ollamaModelKey)
    }

    func refreshStatus() async {
        status = .checking

        switch provider {
        case .appleIntelligence:
            status = AppleIntelligenceEngine.status()
        case .ollama:
            do {
                let models = try await OllamaEngine().availableModels()
                availableOllamaModels = models

                guard let firstModel = models.first else {
                    status = ProviderStatus(
                        state: .waiting,
                        title: "No Ollama models",
                        detail: "Install one local model to continue.",
                        symbolName: "shippingbox"
                    )
                    return
                }

                if ollamaModel.isEmpty || !models.contains(ollamaModel) {
                    setOllamaModel(firstModel)
                }

                status = ProviderStatus(
                    state: .ready,
                    title: "Ollama ready",
                    detail: ollamaModel,
                    symbolName: "desktopcomputer"
                )
            } catch {
                availableOllamaModels = []
                status = ProviderStatus(
                    state: .unavailable,
                    title: "Ollama not found",
                    detail: "Start Ollama on this Mac, then check again.",
                    symbolName: "desktopcomputer.trianglebadge.exclamationmark"
                )
            }
        }
    }

    func rewrite() async {
        let source = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            errorMessage = RewriteEngineError.emptySelection.localizedDescription
            return
        }

        isRewriting = true
        errorMessage = nil
        defer { isRewriting = false }

        do {
            outputText = try await RewriteRunner.rewrite(
                provider: provider,
                intent: selectedIntent,
                text: source,
                ollamaModel: ollamaModel
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyOutput() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }

    func useOutputAsInput() {
        guard !outputText.isEmpty else { return }
        inputText = outputText
        outputText = ""
        errorMessage = nil
    }
}
