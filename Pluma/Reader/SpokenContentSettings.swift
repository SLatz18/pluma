import AppKit
import Foundation

/// Opens the System Settings pane where Premium / Enhanced voices download.
enum SpokenContentSettings {
    static func open() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
