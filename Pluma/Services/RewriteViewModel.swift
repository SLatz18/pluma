import AppKit
import Foundation

@MainActor
final class RewriteViewModel: ObservableObject {
    @Published private(set) var provider: RewriteProviderChoice
    @Published private(set) var chain: [RewriteIntent]
    @Published private(set) var status: ProviderStatus = .checking
    @Published var inputText = "hey just checking in - did you get a chance to look at the deck? the numbers arent great tbh, happy to clean them up before tomorrows meeting if that helps"
    @Published var outputText = ""
    @Published var ollamaModel: String
    @Published private(set) var availableOllamaModels: [String] = []
    @Published private(set) var isRewriting = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = Preferences.provider(from: defaults)
        chain = Preferences.chain(from: defaults)
        ollamaModel = Preferences.ollamaModel(from: defaults)
    }

    func selectProvider(_ newProvider: RewriteProviderChoice) {
        provider = newProvider
        defaults.set(newProvider.rawValue, forKey: Preferences.providerKey)
        Task { await refreshStatus() }
    }

    // Tap order is run order; tapping a step that's in the chain pulls it
    // out. Empty is legal — the run surfaces say "pick a recipe" instead.
    func toggleInChain(_ intent: RewriteIntent) {
        if let index = chain.firstIndex(of: intent) {
            chain.remove(at: index)
        } else {
            chain.append(intent)
        }
        Preferences.saveChain(chain, to: defaults)
        outputText = ""
        errorMessage = nil
    }

    func removeFromChain(_ intent: RewriteIntent) {
        guard let index = chain.firstIndex(of: intent) else { return }
        chain.remove(at: index)
        Preferences.saveChain(chain, to: defaults)
        outputText = ""
        errorMessage = nil
    }

    /// One word when it's a single recipe, the arrow pipeline otherwise —
    /// used anywhere the UI names what a run will do.
    var chainDisplay: String {
        chain.isEmpty ? "Pick a recipe" : chain.map(\.title).joined(separator: " → ")
    }

    var runLabel: String {
        switch chain.count {
        case 0: "Pick a recipe"
        case 1: chain[0].title
        default: "Run \(chain.count) steps"
        }
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
        guard !chain.isEmpty else {
            errorMessage = RewriteEngineError.emptyChain.localizedDescription
            return
        }

        isRewriting = true
        errorMessage = nil
        defer { isRewriting = false }

        do {
            // Intermediate results land in the result box as each step
            // finishes, so a chain visibly moves through its pipeline.
            outputText = ""
            outputText = try await RewriteRunner.rewriteChain(
                provider: provider,
                steps: chain,
                text: source,
                ollamaModel: ollamaModel,
                onProgress: { progress in
                    if case .stepFinished(_, _, let output) = progress {
                        self.outputText = output
                    }
                }
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
