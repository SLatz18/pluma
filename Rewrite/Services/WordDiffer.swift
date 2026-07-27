import Foundation

/// A word-level diff between the original and rewritten text.
/// This is the ground truth for the HUD's change summary — it is computed
/// locally and never depends on model claims about what changed.
struct DiffSegment: Equatable {
    enum Kind: Equatable {
        case unchanged
        case removed
        case added
    }

    let kind: Kind
    let text: String
}

enum WordDiffer {
    /// Returns display segments from an LCS diff over whitespace-separated
    /// tokens. Fine for message-length text (a few hundred words).
    static func diff(original: String, revised: String) -> [DiffSegment] {
        let a = tokenize(original)
        let b = tokenize(revised)

        // LCS table
        var table = [[Int]](
            repeating: [Int](repeating: 0, count: b.count + 1),
            count: a.count + 1
        )
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var segments: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                segments.append(DiffSegment(kind: .unchanged, text: a[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                segments.append(DiffSegment(kind: .removed, text: a[i]))
                i += 1
            } else {
                segments.append(DiffSegment(kind: .added, text: b[j]))
                j += 1
            }
        }
        while i < a.count {
            segments.append(DiffSegment(kind: .removed, text: a[i]))
            i += 1
        }
        while j < b.count {
            segments.append(DiffSegment(kind: .added, text: b[j]))
            j += 1
        }
        return segments
    }

    /// Number of changed word runs (an adjacent removed+added pair counts once).
    static func changeCount(_ segments: [DiffSegment]) -> Int {
        var count = 0
        var inChange = false
        var sawRemoved = false
        for segment in segments {
            switch segment.kind {
            case .unchanged:
                inChange = false
                sawRemoved = false
            case .removed:
                if !inChange {
                    count += 1
                    inChange = true
                }
                sawRemoved = true
            case .added:
                if !inChange || !sawRemoved {
                    if !inChange { count += 1 }
                    inChange = true
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
