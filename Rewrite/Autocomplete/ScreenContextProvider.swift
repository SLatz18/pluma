import AppKit
import ScreenCaptureKit
import Vision

@MainActor
final class ScreenContextProvider {
    static let shared = ScreenContextProvider()

    private(set) var isPermitted: Bool
    private var monitorTask: Task<Void, Never>?

    var onChange: ((Bool) -> Void)?

    init() {
        isPermitted = CGPreflightScreenCaptureAccess()
    }

    func refresh() {
        let permitted = CGPreflightScreenCaptureAccess()
        guard permitted != isPermitted else { return }
        isPermitted = permitted
        onChange?(permitted)
    }

    func requestPermission() {
        CGRequestScreenCaptureAccess()
        openSystemSettings()
        refresh()
    }

    func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        else { return }
        NSWorkspace.shared.open(url)
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

    // Runs off the main actor: capture plus OCR take a few hundred
    // milliseconds and must never stall the UI.
    nonisolated static func surroundingText() async -> String? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard
            let frontmost = NSWorkspace.shared.frontmostApplication,
            let frontmostBundleID = frontmost.bundleIdentifier,
            frontmostBundleID != Bundle.main.bundleIdentifier
        else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard
                let window = content.windows
                    .filter({
                        $0.owningApplication?.bundleIdentifier == frontmostBundleID
                            && $0.frame.width > 200 && $0.frame.height > 200
                    })
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { return nil }

            let scale: CGFloat = 2
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )

            return try ocr(image)
        } catch {
            DebugLog.log("screen context failed: \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated static func ocr(_ image: CGImage) throws -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let results = request.results, !results.isEmpty else { return nil }
        let lines = results.compactMap { $0.topCandidates(1).first?.string }
        let full = lines.joined(separator: "\n")
        return String(full.suffix(1_200))
    }
}
