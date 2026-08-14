import AppKit
import ScreenCaptureKit
import Vision

@MainActor
final class ScreenContextProvider {
    static let shared = ScreenContextProvider()

    private(set) var isPermitted: Bool
    private let poller = PermissionPoller()

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
        PrivacySettingsPane.open("Privacy_ScreenCapture")
    }

    func startMonitoring() {
        poller.start { [weak self] in self?.refresh() }
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
            DebugLog.log("screen context failed: \(error.localizedDescription)", at: .quiet)
            return nil
        }
    }

    // Recognition bias wants discrete terms, not prose. Proper nouns and
    // unusual words are what the speech model gets wrong and what OCR is most
    // likely to have on screen, so keep those and drop ordinary vocabulary.
    nonisolated static func contextualStrings(from text: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []

        for token in text.components(separatedBy: tokenSeparators) {
            let term = token.trimmingCharacters(in: .punctuationCharacters)
            guard term.count >= 3, term.count <= 40 else { continue }
            guard term.rangeOfCharacter(from: .letters) != nil else { continue }
            guard let first = term.first else { continue }

            let isCapitalized = first.isUppercase
            let hasInnerCaps = term.dropFirst().contains { $0.isUppercase }
            let hasDigits = term.rangeOfCharacter(from: .decimalDigits) != nil
            guard isCapitalized || hasInnerCaps || hasDigits else { continue }
            guard !commonWords.contains(term.lowercased()) else { continue }

            guard seen.insert(term.lowercased()).inserted else { continue }
            terms.append(term)
            if terms.count >= maximumContextualStrings { break }
        }

        return terms
    }

    private nonisolated static let maximumContextualStrings = 60

    private nonisolated static let tokenSeparators = CharacterSet
        .whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "|/\\()[]{}<>,;:\"'“”‘’•…"))

    // Sentence-initial capitals make ordinary words look like proper nouns;
    // biasing toward these would waste the budget and skew common words.
    private nonisolated static let commonWords: Set<String> = [
        "the", "and", "but", "for", "with", "from", "this", "that", "these",
        "those", "you", "your", "our", "their", "they", "them", "there", "here",
        "what", "when", "where", "which", "who", "why", "how", "all", "any",
        "can", "will", "would", "should", "could", "have", "has", "had", "not",
        "are", "was", "were", "been", "being", "into", "out", "off", "over",
        "then", "than", "now", "new", "get", "got", "see", "say", "said",
        "hi", "hey", "hello", "thanks", "thank", "please", "sorry", "yes", "no",
        "one", "two", "three", "some", "more", "most", "other", "also", "just",
        "like", "want", "need", "make", "made", "know", "think", "let", "may",
        "sent", "reply", "inbox", "search", "menu", "file", "edit", "view",
        "window", "help", "done", "cancel", "close", "open", "save", "send"
    ]

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
