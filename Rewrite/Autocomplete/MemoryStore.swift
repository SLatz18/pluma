import Foundation

@MainActor
final class MemoryStore: ObservableObject {
    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let date: Date
        let text: String

        init(date: Date, text: String) {
            id = UUID()
            self.date = date
            self.text = text
        }
    }

    static let shared = MemoryStore()

    @Published private(set) var entries: [Entry] = []
    let url: URL
    private let maxEntries = 300

    init(url: URL? = nil) {
        let resolved = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Rewrite", directoryHint: .isDirectory)
            .appending(path: "writing-memory.json")
        self.url = resolved
        try? FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    var count: Int { entries.count }

    func record(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 3 else { return }
        guard entries.last?.text != cleaned else { return }
        entries.append(Entry(date: .now, text: cleaned))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        save()
    }

    func digest(maxEntries: Int = 12, maxCharacters: Int = 900) -> String? {
        guard !entries.isEmpty else { return nil }
        var seen = Set<String>()
        var lines: [String] = []
        for entry in entries.reversed() {
            if seen.insert(entry.text.lowercased()).inserted {
                lines.append("- \(entry.text)")
            }
            if lines.count >= maxEntries { break }
        }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : String(joined.prefix(maxCharacters))
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
