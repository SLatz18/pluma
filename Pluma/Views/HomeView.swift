import SwiftUI

/// Home: set the system-wide shortcut, pick a recipe pipeline, then try it
/// here before using it in another app.
struct HomeView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @EnvironmentObject private var selectionRewrite: SelectionRewriteController

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        DSFeaturePage(
            .rewrite,
            subtitle: "Select text, run a recipe pipeline, and keep your meaning."
        ) {
            AnywhereCard()

            DSSection(
                "Recipe",
                detail: "Choose recipes in the order they should run."
            ) {
                LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                    ForEach(RewriteIntent.allCases) { intent in
                        RecipeActionCard(
                            intent: intent,
                            stepNumber: model.chain.firstIndex(of: intent).map { $0 + 1 }
                        ) {
                            model.toggleInChain(intent)
                        }
                    }
                }
            }

            pipelineStrip

            DSSection("Result", detail: "Try the same pipeline before using it in another app.") {
                PlaygroundView()
                    .environmentObject(model)
            }

            DSSharedSettingLink(
                title: "Writing model",
                value: "\(model.provider.title) · \(model.status.title)",
                systemImage: "brain",
                destination: .writing
            )
            .dsCard()
        }
        .task {
            await model.refreshStatus()
        }
    }

    // Trigger on the left, ordered steps after — exactly what the hotkey and
    // the playground will run.
    private var pipelineStrip: some View {
        DSPipelineStrip(isEmpty: model.chain.isEmpty) {
            DSEmptyState(
                title: "No recipe steps",
                detail: "Choose a recipe above. The same pipeline runs here and on selected text with \(selectionRewrite.shortcut.display).",
                systemImage: "sparkles.rectangle.stack"
            )
        } content: {
            triggerPill

            ForEach(Array(model.chain.enumerated()), id: \.element) { index, intent in
                DSPipelineConnector()

                DSPipelineStep(
                    title: intent.title,
                    number: index + 1,
                    tint: intent.feature.color,
                    moveLeft: index > 0
                        ? { model.moveInChain(intent, offset: -1) }
                        : nil,
                    moveRight: index < model.chain.count - 1
                        ? { model.moveInChain(intent, offset: 1) }
                        : nil
                ) {
                    model.removeFromChain(intent)
                }
            }
        }
    }

    private var triggerPill: some View {
        DSBadge(
            text: selectionRewrite.shortcut.display,
            tone: .neutral,
            systemImage: "keyboard"
        )
        .accessibilityLabel("Trigger: press \(selectionRewrite.shortcut.display)")
    }

}
