import SwiftUI

struct DictationHUDView: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            if text.isEmpty {
                Text("Listening…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                // Volatile results get revised as more audio arrives, so keep
                // the tail visible rather than the beginning.
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
    }
}
