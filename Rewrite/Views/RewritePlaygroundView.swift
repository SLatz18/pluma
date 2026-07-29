import SwiftUI

struct RewritePlaygroundView: View {
    @EnvironmentObject private var model: RewriteViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Try it here")
                        .font(DS.cardTitle)
                    Text("Your text never leaves this Mac.")
                        .font(DS.meta)
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
                    .font(DS.meta)
                    .foregroundStyle(.red)
            }
        }
        .dsCard()
    }

    private func editor(
        title: String,
        text: Binding<String>,
        isEditable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.eyebrow)
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(
                    DS.insetBackground,
                    in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
                )
                .disabled(!isEditable)
        }
        .frame(maxWidth: .infinity)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RESULT")
                    .font(DS.eyebrow)
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
                ZStack(alignment: .topLeading) {
                    if model.outputText.isEmpty {
                        Text("Your rewritten text will appear here.")
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    } else {
                        Text(model.outputText)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.outputText.isEmpty)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(
                DS.insetBackground,
                in: RoundedRectangle(cornerRadius: DS.insetRadius, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity)
    }
}
