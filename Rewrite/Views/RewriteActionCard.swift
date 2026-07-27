import SwiftUI

struct RewriteActionCard: View {
    let intent: RewriteIntent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: intent.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(intent.tint)
                    .frame(width: 42, height: 42)
                    .background(
                        intent.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("SELECTED TEXT")
                            .font(.caption2.weight(.bold))
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }

                    Text(intent.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(intent.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? intent.tint : Color.secondary.opacity(0.35))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(
                isSelected
                    ? intent.tint.opacity(0.075)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? intent.tint.opacity(0.5) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(intent.title): \(intent.shortDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension RewriteIntent {
    var tint: Color {
        switch self {
        case .improve: .blue
        case .shorten: .purple
        case .grammar: .green
        case .professional: .orange
        }
    }
}
