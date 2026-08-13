import Foundation

/// Aliases Caps Lock → F18 at the HID driver so the OS stops treating Caps as
/// a toggle. Invisible to the user: they still press the Caps Lock key; F18
/// never appears in Settings or shortcut labels.
///
/// Uses `hidutil` (Apple TN2450). Mapping is session-scoped and clears on
/// reboot. We only add/remove *our* Caps→F18 entry — never wipe the user's
/// other remaps (Caps→Esc, etc.).
enum CapsLockHIDRemap {
    /// Caps Lock HID usage (keyboard page).
    static let capsLockUsage: UInt64 = 0x7000_00039
    /// F18 — no physical key on Apple keyboards.
    static let f18Usage: UInt64 = 0x7000_0006D

    /// Adds pluma's Caps→F18 entry.
    /// - Returns: JSON for the mapping list *without* pluma's entry — the exact
    ///   state to restore on teardown or crash (see `CapsLockGuardian`).
    @discardableResult
    static func apply() throws -> String {
        var entries = try currentEntries()
        entries.removeAll { isOurMapping($0) }
        let restoreJSON = try encodeEntries(entries)
        entries.append(ourMapping)
        try setEntries(entries)
        return restoreJSON
    }

    /// Removes only pluma's Caps→F18 mapping. Leaves every other entry alone.
    static func clearOurMapping() throws {
        var entries = try currentEntries()
        let before = entries.count
        entries.removeAll { isOurMapping($0) }
        guard entries.count != before else { return }
        try setEntries(entries)
    }

    static func isOurMappingPresent() -> Bool {
        (try? currentEntries().contains(where: isOurMapping)) ?? false
    }

    // MARK: - Private

    private struct Entry: Codable, Equatable {
        var HIDKeyboardModifierMappingSrc: UInt64
        var HIDKeyboardModifierMappingDst: UInt64
    }

    private static let ourMapping = Entry(
        HIDKeyboardModifierMappingSrc: capsLockUsage,
        HIDKeyboardModifierMappingDst: f18Usage
    )

    private static func isOurMapping(_ entry: Entry) -> Bool {
        entry.HIDKeyboardModifierMappingSrc == capsLockUsage
            && entry.HIDKeyboardModifierMappingDst == f18Usage
    }

    private static func currentEntries() throws -> [Entry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CapsLockHIDRemapError.hidutilFailed(stderrString(stderr))
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Empty / null / () means no mapping.
        if text.isEmpty || text == "null" || text == "()" || text == "(null)" {
            return []
        }
        // hidutil prints an Obj-C style plist dump for some macOS versions and
        // JSON-ish output for others. Prefer JSON; fall back to scanning for
        // our known usage pair.
        if let jsonData = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Entry].self, from: jsonData) {
            return decoded
        }
        // Plist-style: look for decimal usage numbers in the dump.
        return parsePlistDump(text)
    }

    private static func parsePlistDump(_ text: String) -> [Entry] {
        // Matches pairs of Src/Dst usage integers in either order of appearance.
        let pattern = #"HIDKeyboardModifierMappingSrc\s*=\s*(\d+).*?HIDKeyboardModifierMappingDst\s*=\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let srcRange = Range(match.range(at: 1), in: text),
                  let dstRange = Range(match.range(at: 2), in: text),
                  let src = UInt64(text[srcRange]),
                  let dst = UInt64(text[dstRange])
            else { return nil }
            return Entry(HIDKeyboardModifierMappingSrc: src, HIDKeyboardModifierMappingDst: dst)
        }
    }

    private static func encodeEntries(_ entries: [Entry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(entries)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CapsLockHIDRemapError.hidutilFailed("failed to encode UserKeyMapping")
        }
        return json
    }

    private static func setEntries(_ entries: [Entry]) throws {
        try runHidutil(setJSON: "{\"UserKeyMapping\":\(try encodeEntries(entries))}")
    }

    private static func runHidutil(setJSON: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", setJSON]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CapsLockHIDRemapError.hidutilFailed(stderrString(stderr))
        }
    }

    private static func stderrString(_ pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "hidutil failed"
    }
}

enum CapsLockHIDRemapError: Error, LocalizedError {
    case hidutilFailed(String)

    var errorDescription: String? {
        switch self {
        case .hidutilFailed(let message):
            message.isEmpty ? "hidutil failed to update Caps Lock mapping" : message
        }
    }
}
