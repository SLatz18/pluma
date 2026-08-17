import AppKit
import SwiftUI

/// Developer sheet: same fixture, two prompt arms, one rewrite provider.
struct PromptABComparisonView: View {
    @EnvironmentObject private var rewrite: RewriteViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PromptABRunner()

    @State private var mode: PromptABMode = .directive
    @State private var intent: RewriteIntent = .improve
    @State private var fixture = ""
    @State private var armA = ""
    @State private var armB = ""
    @State private var didPromote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                editors

                if let resultA = runner.resultA {
                    armSection(resultA, promoteLabel: "Promote A → override")
                }
                if let resultB = runner.resultB {
                    armSection(resultB, promoteLabel: "Promote B → override")
                }
            }
            .padding(18)
        }
        .frame(width: 660, height: 680)
        .onAppear {
            if fixture.isEmpty {
                fixture = rewrite.inputText
            }
            reloadArmDefaults()
        }
        .onChange(of: mode) { _, _ in reloadArmDefaults() }
        .onChange(of: intent) { _, _ in
            if mode == .directive {
                reloadArmDefaults()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Prompt A/B")
                .font(.headline)
            Text(mode.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Uses \(rewrite.provider.title)\(providerDetail). Results stay in this sheet — nothing is stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providerDetail: String {
        switch rewrite.provider {
        case .ollama:
            rewrite.ollamaModel.isEmpty ? "" : " · \(rewrite.ollamaModel)"
        case .appleIntelligence:
            ""
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(PromptABMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .directive {
                Picker("Recipe", selection: $intent) {
                    ForEach(RewriteIntent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Picker("Recipe for both arms", selection: $intent) {
                    ForEach(RewriteIntent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Run A/B") {
                    Task {
                        await runner.run(
                            fixture: fixture,
                            mode: mode,
                            intent: intent,
                            armA: armA,
                            armB: armB,
                            provider: rewrite.provider,
                            ollamaModel: rewrite.ollamaModel
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isBusy || !canRun)

                Button("Swap arms") {
                    let previous = armA
                    armA = armB
                    armB = previous
                    didPromote = nil
                }
                .disabled(runner.isBusy)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") { dismiss() }
            }

            if let didPromote {
                Text("Promoted \(didPromote) — next rewrite uses it.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var editors: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledEditor(title: "Fixture", text: $fixture, minHeight: 72)

            HStack(alignment: .top, spacing: 12) {
                labeledEditor(title: "Arm A", text: $armA, minHeight: 100)
                labeledEditor(title: "Arm B", text: $armB, minHeight: 100)
            }
        }
    }

    private func armSection(_ result: PromptABArmResult, promoteLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result \(result.label)")
                    .font(DS.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2fs", result.seconds))
                    .font(DS.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(promoteLabel) {
                    runner.promote(
                        label: result.label,
                        mode: mode,
                        intent: intent,
                        armA: armA,
                        armB: armB
                    )
                    didPromote = result.label
                }
                .controlSize(.small)
                .disabled(result.output == nil)

                if let output = result.output, !output.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                    .controlSize(.small)
                }
            }

            DSInset {
                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    if let output = result.output, !output.isEmpty {
                        Text(output)
                            .font(DS.meta)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(result.failure ?? "No output")
                            .font(DS.meta)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DisclosureGroup("Show composed prompt") {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            composedBlock(title: "System", body: result.composed.system)
                            composedBlock(title: "User", body: result.composed.user)
                        }
                        .padding(.top, DS.Spacing.xSmall)
                    }
                    .font(DS.meta)
                }
            }
        }
    }

    private func composedBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(DS.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(body, forType: .string)
                }
                .controlSize(.mini)
            }
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labeledEditor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(DS.eyebrow)
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .dsInsetSurface()
        }
        .frame(maxWidth: .infinity)
    }

    private var canRun: Bool {
        !fixture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !armA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !armB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch runner.phase {
        case .idle: "Edit A and B, then run."
        case .runningA: "Running arm A…"
        case .runningB: "Running arm B…"
        case .done: "Done."
        case .failed(let reason): reason
        }
    }

    private func reloadArmDefaults() {
        switch mode {
        case .directive:
            armA = intent.shippedDirective
            armB = PromptOverrides.text(for: intent.promptID, default: intent.shippedDirective)
        case .system:
            armA = PromptComposer.shippedSystemInstructions
            armB = PromptComposer.systemInstructions
        }
        didPromote = nil
    }
}
