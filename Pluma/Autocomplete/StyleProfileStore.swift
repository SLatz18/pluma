import Foundation

@MainActor
final class StyleProfileStore: ObservableObject {
    static let shared = StyleProfileStore()

    // The on-device model's context is small; an overlong profile crowds out
    // the actual completion context.
    static let maxCharacters = 3_000

    @Published private(set) var text: String
    let url: URL

    init(url: URL? = nil) {
        let resolved = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Pluma", directoryHint: .isDirectory)
            .appending(path: "style-profile.md")
        self.url = resolved
        try? FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        text = (try? String(contentsOf: resolved, encoding: .utf8)) ?? ""
    }

    var isEmpty: Bool { text.isEmpty }

    func setText(_ newText: String) {
        let cleaned = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        text = String(cleaned.prefix(Self.maxCharacters))
        save()
    }

    func importContents(of fileURL: URL) throws {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        setText(Self.stripFrontmatter(raw))
    }

    func clear() {
        text = ""
        save()
    }

    // Skill files carry YAML frontmatter that would only confuse the model.
    static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lines = text.components(separatedBy: "\n")
        guard
            let end = lines[1...].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            })
        else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines[(end + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
