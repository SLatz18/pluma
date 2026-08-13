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

    struct Entry: Codable, Equatable {
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
        return entries(fromDump: text)
    }

    /// Parses `hidutil property --get UserKeyMapping` output.
    ///
    /// Internal for testing. hidutil prints an OpenStep-style plist on current
    /// macOS and JSON on others, and **it does not guarantee key order** — real
    /// output lists `Dst` before `Src`. Reading the pair positionally is the bug
    /// that made every poll believe the mapping was absent and re-apply it.
    static func entries(fromDump text: String) -> [Entry] {
        if let data = text.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
                return decoded
            }
            // OpenStep plists carry no number type, so values arrive as strings.
            if let list = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [[String: Any]] {
                let parsed = list.compactMap(entry(fromDictionary:))
                if !parsed.isEmpty { return parsed }
            }
        }
        // Last resort: scan each brace-delimited block on its own so a Src and a
        // Dst can never be paired across two different entries.
        return text.components(separatedBy: "}").compactMap { block in
            guard let src = usage("HIDKeyboardModifierMappingSrc", in: block),
                  let dst = usage("HIDKeyboardModifierMappingDst", in: block)
            else { return nil }
            return Entry(HIDKeyboardModifierMappingSrc: src, HIDKeyboardModifierMappingDst: dst)
        }
    }

    private static func entry(fromDictionary dict: [String: Any]) -> Entry? {
        guard let src = usage(dict["HIDKeyboardModifierMappingSrc"]),
              let dst = usage(dict["HIDKeyboardModifierMappingDst"])
        else { return nil }
        return Entry(HIDKeyboardModifierMappingSrc: src, HIDKeyboardModifierMappingDst: dst)
    }

    private static func usage(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber: number.uint64Value
        case let string as String: parseUsage(string)
        default: nil
        }
    }

    /// hidutil accepts and echoes both hex (`0x700000039`) and decimal.
    private static func parseUsage(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        return UInt64(trimmed)
    }

    private static func usage(_ key: String, in block: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(
            pattern: "\(key)\\s*=\\s*\"?(0[xX][0-9a-fA-F]+|\\d+)\"?"
        ) else { return nil }
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        guard let match = regex.firstMatch(in: block, range: range),
              match.numberOfRanges == 2,
              let valueRange = Range(match.range(at: 1), in: block)
        else { return nil }
        return parseUsage(String(block[valueRange]))
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
