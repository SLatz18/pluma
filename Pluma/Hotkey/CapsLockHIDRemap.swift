import Foundation

/// Aliases Caps Lock → F18 at the HID driver so the OS stops treating Caps as
/// a toggle. Invisible to the user: they still press the Caps Lock key; F18
/// never appears in Settings or shortcut labels.
///
/// Uses `hidutil` (Apple TN2450). Mapping is session-scoped and clears on
/// reboot; we re-apply on enable and always clear on disable/quit.
enum CapsLockHIDRemap {
    /// Caps Lock HID usage (keyboard page).
    static let capsLockUsage: UInt64 = 0x7000_00039
    /// F18 — no physical key on Apple keyboards.
    static let f18Usage: UInt64 = 0x7000_0006D

    static func apply() throws {
        try runHidutil(setJSON: """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(capsLockUsage),\
        "HIDKeyboardModifierMappingDst":\(f18Usage)}]}
        """)
    }

    static func clear() throws {
        try runHidutil(setJSON: #"{"UserKeyMapping":[]}"#)
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
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "hidutil failed"
            throw CapsLockHIDRemapError.hidutilFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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
