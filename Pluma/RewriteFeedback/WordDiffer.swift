import Foundation

/// A local word-level diff used by the rewrite feedback card. Model output is
/// never trusted to describe its own changes.
struct DiffSegment: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case unchanged
        case removed
        case added
    }

    let kind: Kind
    let text: String
}

enum WordDiffer {
    /// LCS gives a stable, readable diff for ordinary selections. Very large
    /// inputs deliberately fall back to a coarse replacement: bounding the
    /// matrix prevents a pasted document from stalling the UI after rewrite.
    static func diff(original: String, revised: String) -> [DiffSegment] {
        let originalWords = tokenize(original)
        let revisedWords = tokenize(revised)

        guard !originalWords.isEmpty else {
            return revisedWords.map { DiffSegment(kind: .added, text: $0) }
        }
        guard !revisedWords.isEmpty else {
            return originalWords.map { DiffSegment(kind: .removed, text: $0) }
        }

        let maximumMatrixCells = 250_000
        guard originalWords.count <= maximumMatrixCells / revisedWords.count else {
            return originalWords.map { DiffSegment(kind: .removed, text: $0) }
                + revisedWords.map { DiffSegment(kind: .added, text: $0) }
        }

        var table = [[Int]](
            repeating: [Int](repeating: 0, count: revisedWords.count + 1),
            count: originalWords.count + 1
        )
        for i in stride(from: originalWords.count - 1, through: 0, by: -1) {
            for j in stride(from: revisedWords.count - 1, through: 0, by: -1) {
                if originalWords[i] == revisedWords[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var segments: [DiffSegment] = []
        var originalIndex = 0
        var revisedIndex = 0
        while originalIndex < originalWords.count, revisedIndex < revisedWords.count {
            if originalWords[originalIndex] == revisedWords[revisedIndex] {
                segments.append(.init(kind: .unchanged, text: originalWords[originalIndex]))
                originalIndex += 1
                revisedIndex += 1
            } else if table[originalIndex + 1][revisedIndex]
                >= table[originalIndex][revisedIndex + 1]
            {
                segments.append(.init(kind: .removed, text: originalWords[originalIndex]))
                originalIndex += 1
            } else {
                segments.append(.init(kind: .added, text: revisedWords[revisedIndex]))
                revisedIndex += 1
            }
        }
        while originalIndex < originalWords.count {
            segments.append(.init(kind: .removed, text: originalWords[originalIndex]))
            originalIndex += 1
        }
        while revisedIndex < revisedWords.count {
            segments.append(.init(kind: .added, text: revisedWords[revisedIndex]))
            revisedIndex += 1
        }
        return segments
    }

    /// Adjacent removals and additions describe one edited passage.
    static func changeCount(_ segments: [DiffSegment]) -> Int {
        var count = 0
        var isInsideChange = false
        for segment in segments {
            switch segment.kind {
            case .unchanged:
                isInsideChange = false
            case .removed, .added:
                if !isInsideChange {
                    count += 1
                    isInsideChange = true
                }
            }
        }
        return count
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}
