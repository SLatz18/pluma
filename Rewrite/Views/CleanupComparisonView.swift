import SwiftUI

struct CleanupComparisonView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = ComparisonRunner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls

                if !runner.transcripts.isEmpty {
                    section("Transcription — same recording, both engines") {
                        ForEach(runner.transcripts) { transcript in
                            resultBox(
                                title: transcript.source,
                                seconds: transcript.seconds,
                                body: transcript.text,
                                failure: transcript.failure
                            )
                        }
                    }
                }

                if !runner.cleanups.isEmpty {
                    section("Cleanup — every transcript through every model") {
                        ForEach(runner.cleanups) { cleanup in
                            resultBox(
                                title: "\(cleanup.transcriber) → \(cleanup.cleaner)",
                                seconds: cleanup.seconds,
                                body: cleanup.output,
                                failure: cleanup.failure
                            )
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 620, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Compare transcription and cleanup")
                .font(.headline)
            Text("Records once, transcribes that single recording with both engines, then runs each transcript through both cleanup models. Neither transcriber gets the on-screen terms, and on-device runs never overlap each other, so no result is handicapped by the way it was measured.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(runner.isRecording ? "Stop and compare" : "Record a sample") {
                if runner.isRecording {
                    Task { await runner.stopAndCompare(openAIModel: controller.openAIModel) }
                } else {
                    runner.startRecording()
                }
            }
            .disabled(runner.isBusy || !OpenAIKey.isPresent)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(runner.isRecording ? .red : .secondary)

            Spacer()

            Button("Done") { dismiss() }
        }
    }

    private var statusText: String {
        switch runner.phase {
        case .idle:
            OpenAIKey.isPresent
                ? "Comparing against \(controller.openAIModel.title)."
                : "Add an OpenAI API key first."
        case .recording: "Recording — say a sentence or two, then stop."
        case .transcribing: "Transcribing with both engines…"
        case .cleaning: "Cleaning up every transcript…"
        case .done: "Done."
        case .failed(let reason): reason
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func resultBox(
        title: String, seconds: Double, body: String?, failure: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(String(format: "%.2fs", seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(failure ?? "No output")
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
