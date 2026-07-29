import Foundation
import os

enum DebugLog {

    // How much detail reaches the log. A message declares the *minimum* level at
    // which it appears, so `.quiet` keeps only what always matters (failures,
    // permission changes, session boundaries) and `.verbose` adds the
    // per-keystroke tracing the caret work needs.
    enum Level: Int, CaseIterable, Identifiable, Sendable {
        case quiet = 0
        case normal = 1
        case verbose = 2

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .quiet: "Quiet"
            case .normal: "Normal"
            case .verbose: "Verbose"
            }
        }

        var detail: String {
            switch self {
            case .quiet: "Failures and state changes only."
            case .normal: "The default — what the app was doing."
            case .verbose: "Adds caret probes and every overlay presentation."
            }
        }
    }

    // Read on every log call from whichever actor is logging, so it needs to be
    // both thread-safe and cheap. An unfair lock is Sendable without
    // @unchecked and costs far less than NSLock on the read path.
    private static let levelStorage = OSAllocatedUnfairLock(initialState: Level.normal)

    static var level: Level {
        get { levelStorage.withLock { $0 } }
        set { levelStorage.withLock { $0 = newValue } }
    }

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
        log("log started", at: .quiet)
    }

    // The message is an autoclosure so a filtered-out call costs one integer
    // compare and nothing else: no interpolation, no CGRect formatting, no
    // allocation. That is what makes it safe to leave verbose tracing inside
    // CaretResolver, which runs on every keystroke.
    static func log(_ message: @autoclosure () -> String, at minimum: Level = .normal) {
        guard minimum.rawValue <= level.rawValue else { return }

        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message())\n"
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
