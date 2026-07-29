import SwiftUI

struct RewriteActionCard: View {
    let intent: RewriteIntent
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? intent.feature.color : Color.secondary.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                isSelected ? intent.feature.color.opacity(0.08) : DS.cardBackground,
                in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? intent.feature.color.opacity(0.55) : DS.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intent.title): \(intent.shortDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
