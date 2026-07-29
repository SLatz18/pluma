import SwiftUI

struct RecipeActionCard: View {
    let intent: RewriteIntent
    /// 1-based position in the pipeline, nil when the recipe isn't a step.
    let stepNumber: Int?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isInChain: Bool { stepNumber != nil }

    var body: some View {
        Button(action: action) {
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
            .padding(DS.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                isInChain ? intent.feature.color.opacity(0.08) : DS.cardBackground,
                in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(
                        isInChain ? intent.feature.color.opacity(0.55) : DS.hairline,
                        lineWidth: isInChain ? 1.5 : 1
                    )
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: stepNumber)
        }
        .buttonStyle(.plain)
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
