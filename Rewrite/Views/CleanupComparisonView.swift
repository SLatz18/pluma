import SwiftUI

struct CleanupComparisonView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.dismiss) private var dismiss

    @State private var transcript = ""
    @State private var attempts: [RewriteRunner.CleanupAttempt] = []
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare cleanup")
                    .font(.headline)
                Text("Runs the same transcript through both models at once, so you are judging the output rather than remembering it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !controller.recentTranscripts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Something you dictated this session")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(controller.recentTranscripts, id: \.self) { recent in
                        Button {
                            transcript = recent
                        } label: {
                            Text(recent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Raw transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $transcript)
                    .font(.system(size: 12))
                    .frame(height: 70)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.12))
                    }
            }

            HStack(spacing: 10) {
                Button(isRunning ? "Running…" : "Run comparison") {
                    run()
                }
                .disabled(isRunning || transcript.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("Comparing Apple on-device against \(controller.openAIModel.title).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Done") { dismiss() }
            }

            if !attempts.isEmpty {
                Divider()
                ForEach(attempts) { attempt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(attempt.label)
                                .font(.caption.weight(.semibold))
                            Text(String(format: "%.2fs", attempt.seconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let output = attempt.output {
                            Text(output)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(attempt.failure ?? "No output")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            if transcript.isEmpty, let first = controller.recentTranscripts.first {
                transcript = first
            }
        }
    }

    private func run() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isRunning = true
        attempts = []
        Task {
            let results = await RewriteRunner.compareCleanup(
                transcript: text,
                openAIModel: controller.openAIModel
            )
            attempts = results
            isRunning = false
        }
    }
}
