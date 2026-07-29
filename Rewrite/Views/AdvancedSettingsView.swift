import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var memory: MemoryStore

    @State private var filter = ""
    @State private var showClearConfirmation = false

    private var filteredEntries: [MemoryStore.Entry] {
        let newestFirst = memory.entries.reversed()
        guard !filter.isEmpty else { return Array(newestFirst) }
        return newestFirst.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
