import AppKit
import Foundation

@MainActor
final class RewriteViewModel: ObservableObject {
    @Published private(set) var provider: RewriteProviderChoice
    @Published private(set) var chain: [RewriteIntent]
    @Published private(set) var status: ProviderStatus = .checking
    @Published var inputText = "yo idk if u c the deck but ngl the numbers r kinda mid rn, lmk if u want me 2 fix em up b4 the meeting tmrw fr fr"
    @Published var outputText = ""
    @Published var ollamaModel: String
    @Published private(set) var availableOllamaModels: [String] = []
    @Published private(set) var isRewriting = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private var statusRefreshID = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = Preferences.provider(from: defaults)
        chain = Preferences.chain(from: defaults)
        ollamaModel = Preferences.ollamaModel(from: defaults)
    }

    var canRewrite: Bool {
        status.isReady
            && !isRewriting
            && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectProvider(_ newProvider: RewriteProviderChoice) {
        guard provider != newProvider else { return }
        provider = newProvider
        defaults.set(newProvider.rawValue, forKey: Preferences.providerKey)
        status = .checking
        outputText = ""
        errorMessage = nil
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
        if provider == .ollama, status.isReady {
            status = ProviderStatus(
                state: .ready,
                title: "Ollama ready",
                detail: model,
                symbolName: "desktopcomputer"
            )
        }
    }

    func refreshStatus() async {
        let refreshID = UUID()
        statusRefreshID = refreshID
        let requestedProvider = provider
        status = .checking

        switch requestedProvider {
        case .appleIntelligence:
            guard statusRefreshID == refreshID, provider == requestedProvider else { return }
            status = AppleIntelligenceEngine.status()
        case .ollama:
            do {
                let models = try await OllamaEngine().availableModels()
                guard statusRefreshID == refreshID, provider == requestedProvider else { return }
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
                guard statusRefreshID == refreshID, provider == requestedProvider else { return }
                availableOllamaModels = []
                status = ProviderStatus(
                    state: .unavailable,
                    title: "Ollama not found",
                    detail: error.localizedDescription,
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

        guard status.isReady else {
            errorMessage = RewriteEngineError
                .providerNotReady(status.detail)
                .localizedDescription
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
