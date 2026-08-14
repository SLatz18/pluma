import AVFoundation

/// Which input device dictation records from. An empty UID means the system
/// default; a stored UID pins one device — typically the built-in mic — so
/// plugging in headphones doesn't silently reroute capture to a worse mic.
enum MicrophoneSelection {
    struct Option: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    /// The tag for "follow the system default" in pickers.
    static let systemDefaultID = ""

    static func availableMicrophones() -> [Option] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { Option(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The device capture should open: the pinned one while it's connected,
    /// otherwise the system default. Never a hard failure — dictation must
    /// still work when the pinned mic is unplugged.
    static func captureDevice(from defaults: UserDefaults = .standard) -> AVCaptureDevice? {
        let uid = Preferences.dictationMicUID(from: defaults)
        if !uid.isEmpty {
            if let pinned = AVCaptureDevice(uniqueID: uid), pinned.isConnected {
                return pinned
            }
            DebugLog.log("pinned microphone unavailable, capturing from system default", at: .quiet)
        }
        return AVCaptureDevice.default(for: .audio)
    }

    /// Whether the pinned device is currently connected. Empty UID (system
    /// default) always counts as available.
    static func isPinnedMicrophoneAvailable(from defaults: UserDefaults = .standard) -> Bool {
        let uid = Preferences.dictationMicUID(from: defaults)
        guard !uid.isEmpty else { return true }
        guard let pinned = AVCaptureDevice(uniqueID: uid) else { return false }
        return pinned.isConnected
    }
}
