import Foundation

/// Which prompt slot the A/B lab varies.
enum PromptABMode: String, CaseIterable, Identifiable, Sendable {
    case directive
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .directive: "Recipe directive"
        case .system: "Rewrite system"
        }
    }

    var detail: String {
        switch self {
        case .directive:
            "Same rewrite system prompt; A and B swap the EDITING GOAL for the chosen recipe."
        case .system:
            "Same recipe directive; A and B swap the rewrite system instructions."
        }
    }
}

struct PromptABComposed: Equatable, Sendable {
    let system: String
    let user: String
}

struct PromptABArmResult: Identifiable, Equatable, Sendable {
    let label: String
    let output: String?
    let failure: String?
    let seconds: Double
    let composed: PromptABComposed

    var id: String { label }
}

/// Runs the same fixture through two prompt arms on one provider, sequentially,
/// so timing stays comparable and on-device work does not contend with itself.
@MainActor
final class PromptABRunner: ObservableObject {
    enum Phase: Equatable {
        case idle
        case runningA
        case runningB
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var resultA: PromptABArmResult?
    @Published private(set) var resultB: PromptABArmResult?

    var isBusy: Bool {
        switch phase {
        case .runningA, .runningB: true
        default: false
        }
    }

    /// Builds the exact system + user payload each arm will send.
    static func composed(
        mode: PromptABMode,
        intent: RewriteIntent,
        armText: String,
        fixture: String
    ) -> PromptABComposed {
        let trimmed = armText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .directive:
            return PromptABComposed(
                system: PromptComposer.systemInstructions,
                user: PromptComposer.userPrompt(directive: trimmed, text: fixture)
            )
        case .system:
            return PromptABComposed(
                system: trimmed,
                user: PromptComposer.userPrompt(directive: intent.directive, text: fixture)
            )
        }
    }

    func run(
        fixture: String,
        mode: PromptABMode,
        intent: RewriteIntent,
        armA: String,
        armB: String,
        provider: RewriteProviderChoice,
        ollamaModel: String
    ) async {
        let text = fixture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed("Paste some fixture text first.")
            return
        }
        let a = armA.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = armB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else {
            phase = .failed("Both arms need prompt text.")
            return
        }

        resultA = nil
        resultB = nil
        phase = .runningA
        resultA = await runArm(
            label: "A",
            armText: a,
            fixture: text,
            mode: mode,
            intent: intent,
            provider: provider,
            ollamaModel: ollamaModel
        )

        phase = .runningB
        resultB = await runArm(
            label: "B",
            armText: b,
            fixture: text,
            mode: mode,
            intent: intent,
            provider: provider,
            ollamaModel: ollamaModel
        )
        phase = .done
    }

    /// Writes the chosen arm into `PromptOverrides` so the next real rewrite uses it.
    func promote(
        label: String,
        mode: PromptABMode,
        intent: RewriteIntent,
        armA: String,
        armB: String
    ) {
        let text = (label == "B" ? armB : armA)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch mode {
        case .directive:
            PromptOverrides.set(
                text,
                for: intent.promptID,
                default: intent.shippedDirective
            )
        case .system:
            PromptOverrides.set(
                text,
                for: PromptOverrides.systemRewriteID,
                default: PromptComposer.shippedSystemInstructions
            )
        }
    }

    private func runArm(
        label: String,
        armText: String,
        fixture: String,
        mode: PromptABMode,
        intent: RewriteIntent,
        provider: RewriteProviderChoice,
        ollamaModel: String
    ) async -> PromptABArmResult {
        let composed = Self.composed(
            mode: mode, intent: intent, armText: armText, fixture: fixture
        )
        let started = ContinuousClock.Instant.now

        do {
            let output: String
            switch mode {
            case .directive:
                output = try await RewriteRunner.rewrite(
                    provider: provider,
                    directive: armText,
                    text: fixture,
                    ollamaModel: ollamaModel
                )
            case .system:
                output = try await withTemporarySystemOverride(armText) {
                    try await RewriteRunner.rewrite(
                        provider: provider,
                        intent: intent,
                        text: fixture,
                        ollamaModel: ollamaModel
                    )
                }
            }
            let cleaned = try RewriteRunner.validatedOutput(output)
            return PromptABArmResult(
                label: label,
                output: cleaned,
                failure: nil,
                seconds: Self.elapsed(since: started),
                composed: composed
            )
        } catch {
            return PromptABArmResult(
                label: label,
                output: nil,
                failure: error.localizedDescription,
                seconds: Self.elapsed(since: started),
                composed: composed
            )
        }
    }

    /// Swap the live rewrite system override for one arm, then restore whatever
    /// was there so a Developer experiment never leaves the store dirty.
    private func withTemporarySystemOverride<T>(
        _ text: String,
        perform: () async throws -> T
    ) async rethrows -> T {
        let id = PromptOverrides.systemRewriteID
        let shipped = PromptComposer.shippedSystemInstructions
        let previous = PromptOverrides.text(for: id, default: shipped)
        PromptOverrides.set(text, for: id, default: shipped)
        defer { PromptOverrides.set(previous, for: id, default: shipped) }
        return try await perform()
    }

    nonisolated private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.Instant.now - start
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}
