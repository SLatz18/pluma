import SwiftUI

/// One tappable directive card in a recipe/pipeline builder. Rewrite,
/// Autocomplete, and Dictation all render their builders with this card so
/// the look and interactions stay identical across features.
struct RecipeActionCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    /// The WHEN half of the card's trigger → action language, e.g.
    /// "Selected text" or "As you type".
    let eyebrow: String
    /// 1-based position in the pipeline, nil when the card isn't a step.
    let stepNumber: Int?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String,
        symbolName: String,
        tint: Color,
        eyebrow: String,
        stepNumber: Int?,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tint = tint
        self.eyebrow = eyebrow
        self.stepNumber = stepNumber
        self.action = action
    }

    init(intent: RewriteIntent, stepNumber: Int?, action: @escaping () -> Void) {
        self.init(
            title: intent.title,
            subtitle: intent.shortDescription,
            symbolName: intent.symbolName,
            tint: intent.feature.color,
            eyebrow: "Selected text",
            stepNumber: stepNumber,
            action: action
        )
    }

    private var isInChain: Bool { stepNumber != nil }

    var body: some View {
        DSSelectableCard(
            isSelected: isInChain,
            tint: tint,
            selectedLineWidth: 1.5,
            action: action
        ) {
            HStack(spacing: 14) {
                DSIconTile(systemImage: symbolName, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    DSEyebrow(trigger: eyebrow)

                    Text(title)
                        .font(DS.cardTitle)
                        .foregroundStyle(.primary)

                    Text(subtitle)
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
                .foregroundStyle(isInChain ? tint : Color.secondary.opacity(0.35))
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
            "\(title): step \(stepNumber) in your pipeline. Tap to remove."
        } else {
            "\(title): \(subtitle). Tap to add to your pipeline."
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
