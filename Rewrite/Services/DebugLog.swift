import Foundation

enum DebugLog {
    static let url: URL = {
        // Keyed off the bundle name so two installs of this app (a release copy
        // and a renamed test build) don't truncate each other's log.
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Rewrite"
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "autocomplete-debug.log")
    }()

    static func truncate() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
        log("log started")
    }

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
