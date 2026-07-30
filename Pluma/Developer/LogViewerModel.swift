import Foundation

struct LogLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

/// Tails `autocomplete-debug.log` in-app so the log can be watched while it is
/// being written, rather than opened after the fact in an editor.
///
/// Like everything else in developer mode it runs **only while the Dev page is
/// on screen**: `start()` from `.onAppear` opens the file and the dispatch
/// source, `stop()` from `.onDisappear` closes both.
@MainActor
final class LogViewerModel: ObservableObject {
    @Published private(set) var lines: [LogLine] = []
    @Published var filter = ""

    // A verbose session can write a lot; seed from the tail rather than reading
    // a log that has been growing all day.
    private static let seedByteLimit = 256 * 1024
    private static let maximumLines = 2_000

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var offset: UInt64 = 0
    private var nextID = 0

    var filteredLines: [LogLine] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return lines }
        return lines.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    func start() {
        guard source == nil else { return }

        descriptor = open(DebugLog.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        seed()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.readAppended()
            }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    func clear() {
        DebugLog.truncate()
        lines = []
        offset = 0
        readAppended()
    }

    private func seed() {
        guard let handle = try? FileHandle(forReadingFrom: DebugLog.url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(Self.seedByteLimit) ? size - UInt64(Self.seedByteLimit) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = size

        var text = String(decoding: data, as: UTF8.self)
        // A mid-line start would render a fragment; drop it.
        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        append(text)
    }

    private func readAppended() {
        guard let handle = try? FileHandle(forReadingFrom: DebugLog.url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        // A smaller file than last time means Clear (or a relaunch) truncated
        // it — start over rather than reading from a stale offset.
        if size < offset {
            lines = []
            offset = 0
        }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = size
        append(String(decoding: data, as: UTF8.self))
    }

    private func append(_ text: String) {
        let incoming = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !incoming.isEmpty else { return }

        for line in incoming {
            lines.append(LogLine(id: nextID, text: String(line)))
            nextID += 1
        }
        if lines.count > Self.maximumLines {
            lines.removeFirst(lines.count - Self.maximumLines)
        }
    }
}
