import SwiftUI

struct RecipeActionCard: View {
    let intent: RewriteIntent
    /// 1-based position in the pipeline, nil when the recipe isn't a step.
    let stepNumber: Int?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isInChain: Bool { stepNumber != nil }

    var body: some View {
        DSSelectableCard(
            isSelected: isInChain,
            tint: intent.feature.color,
            selectedLineWidth: 1.5,
            action: action
        ) {
            HStack(spacing: 14) {
                DSIconTile(systemImage: intent.symbolName, tint: intent.feature.color)

                VStack(alignment: .leading, spacing: 4) {
                    DSEyebrow(trigger: "Selected text")

                    Text(intent.title)
                        .font(DS.cardTitle)
                        .foregroundStyle(.primary)

                    Text(intent.shortDescription)
                        .font(DS.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Group {
                    if let stepNumber {
                        Image(systemName: "\(stepNumber).circle.fill")
                    } else {
                        Image(systemName: "plus.circle")
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isInChain ? intent.feature.color : Color.secondary.opacity(0.35))
                .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: stepNumber)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isInChain ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        if let stepNumber {
            "\(intent.title): step \(stepNumber) in your pipeline. Tap to remove."
        } else {
            "\(intent.title): \(intent.shortDescription). Tap to add to your pipeline."
        }
    }
}

extension RewriteIntent {
    var feature: DS.Feature {
        switch self {
        case .improve: .improve
        case .shorten: .shorten
        case .grammar: .grammar
        case .professional: .professional
        }
    }
}
