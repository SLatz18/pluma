import SwiftUI

/// The change-summary HUD shown after a hotkey rewrite (issue #13).
/// macOS-native card with the app's IFTTT-style trigger→action strip.
/// The corrected text is already on the clipboard before this appears —
/// the HUD informs, it never gates.
struct RewriteHUDView: View {
    enum Mode {
        case result(original: String, revised: String, intent: RewriteIntent)
        case hint(String)
    }

    let mode: Mode
    let onUndo: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch mode {
            case .result(let original, let revised, let intent):
                resultBody(original: original, revised: revised, intent: intent)
            case .hint(let message):
                hintBody(message)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(1) // hairline room
    }

    // MARK: - Full result card

    private func resultBody(original: String, revised: String, intent: RewriteIntent) -> some View {
        let segments = WordDiffer.diff(original: original, revised: revised)
        let changes = WordDiffer.changeCount(segments)

        return VStack(alignment: .leading, spacing: 12) {
            // IFTTT-style recipe strip
            HStack(spacing: 8) {
                recipeNode(icon: "doc.on.clipboard", title: "Copied text", tint: .secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                recipeNode(icon: intent.symbolName, title: intent.title, tint: .green)

                Spacer(minLength: 4)

                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            // Change summary pill
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("\(changes) \(changes == 1 ? "change" : "changes") — ready to paste")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.green.opacity(0.14), in: Capsule())

            // Inline diff (local, ground truth)
            ScrollView {
                diffView(segments)
                    .font(.callout)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 220)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(0.8),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .accessibilityLabel("Rewritten text. \(revised)")

            // Footer
            HStack {
                HStack(spacing: 4) {
                    Text("\u{2318}V")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    Text("to paste")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let onUndo {
                    Button("\u{21A9} Restore clipboard", action: onUndo)
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }

                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(intent.title) complete. \(changes) \(changes == 1 ? "change" : "changes"). Ready to paste."
        )
    }

    // MARK: - Minimal hint

    private func hintBody(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    private func recipeNode(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint == .green ? Color.green : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            (tint == .green ? Color.green.opacity(0.14) : Color.primary.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func diffView(_ segments: [DiffSegment]) -> some View {
        segments.reduce(Text("")) { acc, segment in
            let next: Text
            switch segment.kind {
            case .unchanged:
                next = Text(segment.text).foregroundStyle(.primary)
            case .removed:
                next = Text(segment.text)
                    .foregroundStyle(Color.red)
                    .strikethrough()
            case .added:
                next = Text(segment.text)
                    .foregroundStyle(Color.green)
                    .fontWeight(.medium)
            }
            return Text("\(acc)\(next)")
        }
    }
}
