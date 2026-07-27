import SwiftUI

struct RewritePlaygroundView: View {
    @EnvironmentObject private var model: RewriteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Try it here")
                        .font(.headline)
                    Text("Your text never leaves this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await model.rewrite() }
                } label: {
                    if model.isRewriting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 82)
                    } else {
                        Label(model.selectedIntent.title, systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack(alignment: .top, spacing: 12) {
                editor(title: "Original", text: $model.inputText, isEditable: true)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 150)

                output
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }

    private func editor(
        title: String,
        text: Binding<String>,
        isEditable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .disabled(!isEditable)
        }
        .frame(maxWidth: .infinity)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RESULT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)

                Spacer()

                if !model.outputText.isEmpty {
                    Button {
                        model.useOutputAsInput()
                    } label: {
                        Image(systemName: "arrow.uturn.left")
                    }
                    .buttonStyle(.plain)
                    .help("Use as original")

                    Button {
                        model.copyOutput()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }

            ScrollView {
                Text(
                    model.outputText.isEmpty
                        ? "Your rewritten text will appear here."
                        : model.outputText
                )
                .font(.body)
                .foregroundStyle(model.outputText.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity)
    }
}
