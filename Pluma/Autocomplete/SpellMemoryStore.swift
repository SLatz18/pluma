import Foundation

// Opt-in map of misspellings the writer has accepted fixes for. Local JSON
// only — same privacy shape as style memory. Lookups are keyed case-insensitively
// so "Teh" and "teh" share a lesson.
@MainActor
final class SpellMemoryStore: ObservableObject {
    struct Entry: Codable, Equatable, Sendable, Identifiable {
        var id: String { key }
        let key: String
        var replacement: String
        var count: Int
        var lastUsed: Date
    }

    static let shared = SpellMemoryStore()
    static let maxEntries = 200

    @Published private(set) var entries: [Entry] = []
    let url: URL

    init(url: URL? = nil) {
        let resolved = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Pluma", directoryHint: .isDirectory)
            .appending(path: "spelling-memory.json")
        self.url = resolved
        try? FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    var count: Int { entries.count }

    // Returns a replacement cased to match how the writer typed the misspelling.
    func lookup(_ misspelling: String) -> String? {
        let key = Self.normalizedKey(misspelling)
        guard let entry = entries.first(where: { $0.key == key }) else { return nil }
        return Self.matchingCase(of: entry.replacement, to: misspelling)
    }

    func record(misspelling: String, replacement: String) {
        let cleanedMiss = misspelling.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFix = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedMiss.count >= 2, cleanedFix.count >= 2 else { return }
        guard cleanedMiss.caseInsensitiveCompare(cleanedFix) != .orderedSame else { return }
        guard SpellCorrection.looksLikeSpellingOf(cleanedMiss, replacement: cleanedFix) else {
            return
        }

        let key = Self.normalizedKey(cleanedMiss)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].replacement = cleanedFix
            entries[index].count += 1
            entries[index].lastUsed = .now
        } else {
            entries.append(
                Entry(key: key, replacement: cleanedFix, count: 1, lastUsed: .now)
            )
        }

        entries.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.lastUsed > rhs.lastUsed
        }
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    nonisolated static func normalizedKey(_ misspelling: String) -> String {
        misspelling.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func matchingCase(of replacement: String, to misspelling: String) -> String {
        guard let first = misspelling.first else { return replacement }
        if misspelling.allSatisfy(\.isUppercase) {
            return replacement.uppercased()
        }
        if first.isUppercase {
            let lower = replacement.lowercased()
            guard let head = lower.first else { return replacement }
            return head.uppercased() + lower.dropFirst()
        }
        return replacement.lowercased()
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
