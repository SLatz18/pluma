import AVFoundation
import AppKit

@MainActor
final class MicrophonePermission {
    static let shared = MicrophonePermission()

    private(set) var isGranted: Bool
    private let poller = PermissionPoller()

    var onChange: ((Bool) -> Void)?

    init() {
        isGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func startMonitoring() {
        poller.start { [weak self] in self?.refresh() }
    }

    func refresh() {
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        guard granted != isGranted else { return }
        isGranted = granted
        onChange?(granted)
    }

    // The system prompt only ever appears once. After a denial the settings
    // pane is the only way back, so send the user there instead.
    func request() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isGranted = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            isGranted = granted
            onChange?(granted)
        case .denied, .restricted:
            openSystemSettings()
        @unknown default:
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        PrivacySettingsPane.open("Privacy_Microphone")
    }
}
