import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var memory: MemoryStore
    @EnvironmentObject private var styleProfile: StyleProfileStore

    @State private var filter = ""
    @State private var showClearConfirmation = false
    @State private var showImporter = false
    @State private var showEditor = false
    @State private var importError: String?

    private var filteredEntries: [MemoryStore.Entry] {
        let newestFirst = memory.entries.reversed()
        guard !filter.isEmpty else { return Array(newestFirst) }
        return newestFirst.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Style profile")
                    .font(.headline)
                Text(
                    styleProfile.isEmpty
                        ? "Import a writing-style guide — e.g. a SKILL.md another AI wrote about your voice — to steer completions. Frontmatter is stripped on import."
                        : "Profile loaded (\(styleProfile.text.count) characters). It guides every completion."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Import from File…") {
                        showImporter = true
                    }
                    if !styleProfile.isEmpty {
                        Button("Edit…") {
                            showEditor = true
                        }
                        Button("Clear") {
                            styleProfile.clear()
                        }
                    }

                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Style memory")
                    .font(.headline)
                Text("Phrases you accepted from suggestions. Only accepted text is ever stored — never keystrokes, never screen contents — and it never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Filter phrases", text: $filter)
                .textFieldStyle(.roundedBorder)

            if memory.entries.isEmpty {
                ContentUnavailableView(
                    "No phrases yet",
                    systemImage: "brain",
                    description: Text("Turn on \"Learn my style\" and accept a few suggestions.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text)
                            .lineLimit(2)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            HStack {
                Text("\(memory.count) of 300 phrases")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([memory.url])
                }

                Button("Diagnostics Log…") {
                    NSWorkspace.shared.open(DebugLog.url)
                }

                Button("Clear All…", role: .destructive) {
                    showClearConfirmation = true
                }
            }
        }
        .padding(20)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                try styleProfile.importContents(of: url)
                importError = nil
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showEditor) {
            StyleProfileEditorSheet(store: styleProfile)
        }
        .confirmationDialog(
            "Clear all remembered phrases?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                memory.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every stored phrase from this Mac and cannot be undone.")
        }
    }
}

private struct StyleProfileEditorSheet: View {
    let store: StyleProfileStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style profile")
                .font(.headline)
            Text("Up to \(StyleProfileStore.maxCharacters) characters; longer text is truncated.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            HStack {
                Text("\(draft.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Save") {
                    store.setText(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear {
            draft = store.text
        }
    }
}
