import SwiftUI

/// Home: pick a recipe, try it on your own text, then take it system-wide
/// with the shortcut strip. Doing lives here; configuring lives on the
/// feature pages.
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
            DSSection(
                "Recipe pipeline",
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

            AnywhereCard()

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
        VStack(alignment: .leading, spacing: 12) {
            DSEyebrow(trigger: "Your pipeline", action: "runs left to right")

            if model.chain.isEmpty {
                DSEmptyState(
                    title: "No recipe steps",
                    detail: "Choose a recipe above. The same pipeline runs here and on selected text with \(selectionRewrite.shortcut.display).",
                    systemImage: "sparkles.rectangle.stack"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        triggerPill

                        ForEach(Array(model.chain.enumerated()), id: \.element) { index, intent in
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)

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
                    .padding(.vertical, 2)
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
