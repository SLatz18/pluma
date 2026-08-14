import AppKit

// macOS posts no notification when a privacy grant changes, so the three
// permission singletons (Accessibility, Microphone, Screen Recording) each
// poll their probe every two seconds while their feature page is watching.
// The loop lived byte-identical in all three; this owns it once.
@MainActor
final class PermissionPoller {
    private var task: Task<Void, Never>?

    func start(_ refresh: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
    }
}

enum PrivacySettingsPane {
    // The query names the pane inside Privacy & Security.
    static func open(_ pane: String) {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
