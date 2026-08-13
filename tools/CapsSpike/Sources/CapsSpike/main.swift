// CapsSpike — minimal observe/status entry for local builds.
// Prefer exercising Caps Lock via Pluma Settings once Input Monitoring is granted.
// See NOTES.md for mechanism choice and Hyperkey observation notes.
import AppKit

@main
enum CapsSpikeMain {
    static func main() {
        print("CapsSpike: see tools/CapsSpike/NOTES.md")
        print("Run Pluma and enable Settings → Use Caps Lock for shortcuts.")
    }
}
