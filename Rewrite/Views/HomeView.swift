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
        ScrollView {
            VStack(alignment: .leading, spacing: DS.sectionGap) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    DSEyebrow(trigger: "Build your pipeline", action: "tap in run order")

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(RewriteIntent.allCases) { intent in
                            RewriteActionCard(
                                intent: intent,
                                stepNumber: model.chain.firstIndex(of: intent).map { $0 + 1 }
                            ) {
                                model.toggleInChain(intent)
                            }
                        }
                    }
                }

                pipelineStrip

                RewritePlaygroundView()
                    .environmentObject(model)

                AnywhereCard()
            }
            .padding(DS.pagePadding)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DS.pageBackground)
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
                Text("Tap recipes above to build your pipeline. It runs in the playground below, and on selected text in any app with \(selectionRewrite.shortcut.display).")
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.cardPadding)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundStyle(DS.hairline)
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        triggerPill

                        ForEach(Array(model.chain.enumerated()), id: \.element) { index, intent in
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)

                            stepPill(intent, number: index + 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var triggerPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .semibold))
            Text(selectionRewrite.shortcut.display)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.insetBackground, in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                .strokeBorder(DS.hairline)
        }
        .accessibilityLabel("Trigger: press \(selectionRewrite.shortcut.display)")
    }

    private func stepPill(_ intent: RewriteIntent, number: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "\(number).circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(intent.feature.color)

            Text(intent.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            Button {
                model.removeFromChain(intent)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(intent.title) from pipeline")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                .strokeBorder(intent.feature.color.opacity(0.35))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rewrite anything.")
                    .font(DS.pageTitle)

                Text("Select text. Pick a recipe. Keep your meaning.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            ProviderMenu()
                .environmentObject(model)
        }
    }
}
