import AppKit
import SwiftUI

/// Developer mode: the hidden home for diagnostic surfaces.
///
/// Two rules govern everything here. **It stays invisible until unlocked** —
/// there is no greyed-out menu item, no disabled section; the Dev page is not
/// in the sidebar at all. And **it stays idle until it is on screen** — the
/// inspector, the log watcher, and the trace panel are all constructed on
/// appearance and torn down on disappearance, because autocomplete and
/// dictation run on every keystroke and a debug tool that polled in the
/// background would be felt.
@MainActor
final class DeveloperMode: ObservableObject {
    @Published private(set) var isUnlocked: Bool
    @Published var logLevel: DebugLog.Level {
        didSet {
            guard logLevel != oldValue else { return }
            DebugLog.level = logLevel
            Preferences.setLogLevel(logLevel, to: defaults)
        }
    }
    // Deliberately not persisted: tracing draws boxes over other apps, and an
    // app that started doing that on its own after a relaunch would be
    // alarming. It also keeps launch honest — nothing developer-related is
    // running until you switch it on in this session.
    @Published var isTracingEnabled = false {
        didSet {
            guard isTracingEnabled != oldValue else { return }
            applyTracing()
        }
    }

    private let defaults: UserDefaults
    private let overlay: SuggestionOverlayController
    private var recognizer = CheatCodeRecognizer()
    private var keyMonitor: Any?
    private var tracePanel: CaretTracePanel?

    init(defaults: UserDefaults = .standard, overlay: SuggestionOverlayController) {
        self.defaults = defaults
        self.overlay = overlay

        let unlocked = Preferences.developerModeEnabled(from: defaults)
        isUnlocked = unlocked
        // A locked app has no business logging verbosely, whatever a previous
        // session left in defaults. Computed up front rather than assigned
        // twice, because property observers are not called during init.
        logLevel = unlocked ? Preferences.logLevel(from: defaults) : .normal
        DebugLog.level = logLevel
    }

    // MARK: Entry

    /// Installed while the main window is open and removed when it closes — the
    /// one piece that must exist before unlocking, so it is scoped as tightly as
    /// it can be. The app is a menu-bar resident, so this is a small fraction of
    /// its life, and a *local* monitor never sees a key pressed in another app.
    func startListeningForCheatCode() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(keyCode: event.keyCode)
            }
            // Always hand the event on: swallowing arrows would break sidebar
            // navigation and every text field in the app.
            return event
        }
    }

    func stopListeningForCheatCode() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        recognizer = CheatCodeRecognizer()
    }

    private func handle(keyCode: UInt16) {
        guard recognizer.accept(keyCode: keyCode, at: .now) else { return }
        setUnlocked(!isUnlocked)
    }

    func setUnlocked(_ unlocked: Bool) {
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        Preferences.setDeveloperModeEnabled(unlocked, to: defaults)
        DebugLog.log("developer mode \(unlocked ? "unlocked" : "locked")", at: .quiet)

        if !unlocked {
            // Locking has to leave nothing running. Verbose logging in
            // particular would otherwise keep costing after the UI was gone.
            isTracingEnabled = false
            logLevel = .normal
        }

        overlay.flash(
            systemImage: unlocked ? "hammer.fill" : "lock.fill",
            message: unlocked ? "Developer mode unlocked" : "Developer mode locked",
            atTopLeftPoint: SuggestionOverlayController.mouseTopLeftPoint(),
            from: .developer
        )
    }

    // MARK: Caret tracing

    private func applyTracing() {
        guard isTracingEnabled else {
            overlay.ghostTrace = nil
            tracePanel?.hide()
            // Released, not hidden: no window lingers at alpha 0.
            tracePanel = nil
            return
        }

        let panel = CaretTracePanel()
        tracePanel = panel
        overlay.ghostTrace = panel
    }

    /// Fed by the caret inspector's poll so the box tracks the cursor even when
    /// no suggestion is showing.
    func traceCaret(_ caret: CaretGeometry?) {
        guard isTracingEnabled, let tracePanel else { return }
        if let caret {
            tracePanel.show(caret: caret, ghostFrame: nil)
        } else {
            tracePanel.hide()
        }
    }
}
