import AVFoundation
import AppKit

@MainActor
final class MicrophonePermission {
    static let shared = MicrophonePermission()

    private(set) var isGranted: Bool
    private var monitorTask: Task<Void, Never>?

    var onChange: ((Bool) -> Void)?

    init() {
        isGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
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
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
