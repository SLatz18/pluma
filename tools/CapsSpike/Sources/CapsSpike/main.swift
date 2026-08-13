// CapsSpike — standalone harness that proves Caps Lock can be Pluma's shortcut
// modifier BEFORE the mechanism ships in Pluma. It uses the exact stack Pluma
// will use:
//
//   Layer 1: HID remap Caps → F18 via `hidutil` (kills toggle + LED)
//   Layer 2: a SESSION CGEventTap (Accessibility only, no Input Monitoring)
//            that treats F18 as hold-to-modify and ORs the Caps chord onto
//            other keys
//   Layer 3: re-arm on tapDisabled + wake/lock
//
// Exit criteria this app lets you verify by eye:
//   1. Lone Caps tap does nothing (no LED, no caps state)
//   2. Caps + key reports "chord fired" with the selected flags
//   3. The status row confirms Accessibility is the only grant needed
//   4. Sleep/wake and lock/unlock recover without relaunch
import SwiftUI
import AppKit
import Carbon.HIToolbox
import IOKit
import IOKit.hidsystem

// MARK: - Real Caps Lock state

/// Physical Caps is aliased to F18, so the OS never toggles caps for us. To
/// keep a lone Caps tap working as a real Caps Lock, we drive the state (and
/// the LED) directly through IOHIDSystem.
enum CapsLockState {
    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var handle: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle)
            == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(handle) }
        return body(handle)
    }

    static func isOn() -> Bool {
        withConnection { handle in
            var state = false
            IOHIDGetModifierLockState(handle, Int32(kIOHIDCapsLockState), &state)
            return state
        } ?? false
    }

    static func toggle() {
        _ = withConnection { handle in
            var state = false
            IOHIDGetModifierLockState(handle, Int32(kIOHIDCapsLockState), &state)
            IOHIDSetModifierLockState(handle, Int32(kIOHIDCapsLockState), !state)
        }
    }
}

// MARK: - HID remap (mirror of Pluma/Hotkey/CapsLockHIDRemap.swift)

enum CapsLockHIDRemap {
    static let capsLockUsage: UInt64 = 0x7000_00039
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

    static func isApplied() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let text = String(
            data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""
        return text.contains("\(f18Usage)")
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
            let err = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            ) ?? "hidutil failed"
            throw NSError(
                domain: "CapsSpike", code: 1,
                userInfo: [NSLocalizedDescriptionKey: err.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }
}

// MARK: - Pure state machine (mirror of Pluma/Hotkey/CapsLockStateMachine.swift)

enum CapsEvent: Sendable { case capsDown, capsUp, otherKey }

/// Dual-role Caps: HOLD it with another key and it is the chord modifier; TAP
/// it alone and it is still a real Caps Lock toggle. A tap only counts if no
/// other key was pressed during the hold and the press was shorter than
/// `tapThreshold` — otherwise a slow "hold and think" never surprises you with
/// caps.
struct CapsMachine: Sendable {
    enum Output: Equatable, Sendable {
        case consume
        case consumeAndToggleCapsLock
        case passUnmodified
        case passWithCapsChord
    }

    var tapThreshold: TimeInterval = 0.3
    var tapTogglesCapsLock = true

    private(set) var capsHeld = false
    private var downAt: TimeInterval = 0
    private var usedAsModifier = false

    mutating func handle(_ event: CapsEvent, at now: TimeInterval) -> Output {
        switch event {
        case .capsDown:
            // Key autorepeat re-sends keyDown; only the first one starts the clock.
            if !capsHeld {
                downAt = now
                usedAsModifier = false
            }
            capsHeld = true
            return .consume
        case .capsUp:
            capsHeld = false
            let wasQuick = (now - downAt) <= tapThreshold
            if tapTogglesCapsLock, !usedAsModifier, wasQuick {
                return .consumeAndToggleCapsLock
            }
            return .consume
        case .otherKey:
            guard capsHeld else { return .passUnmodified }
            usedAsModifier = true
            return .passWithCapsChord
        }
    }
}

// MARK: - Event record for the live feed

struct EventRecord: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let label: String
    let keyCode: Int64
    let verdict: String
}

// MARK: - Tap state (NSLock-guarded, safe inside the C callback)

final class TapState: @unchecked Sendable {
    let lock = NSLock()
    var machine = CapsMachine()
    var tap: CFMachPort?
    var capsFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    var capsHeldMirror = false
    var chordFireCount = 0
    var capsTapCount = 0
    var events: [EventRecord] = []

    static let aliasKeyCode = Int64(kVK_F18)

    func process(type: CGEventType, keyCode: Int64) -> CapsMachine.Output {
        lock.lock(); defer { lock.unlock() }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            record(label: "tap re-enabled", keyCode: -1, verdict: "rearm")
            return .passUnmodified
        }

        let isAlias = keyCode == Self.aliasKeyCode
        let event: CapsEvent
        if isAlias, type == .keyDown { event = .capsDown }
        else if isAlias, type == .keyUp { event = .capsUp }
        else if type == .keyDown || type == .keyUp { event = .otherKey }
        else { return .passUnmodified }

        let output = machine.handle(event, at: CFAbsoluteTimeGetCurrent())
        capsHeldMirror = machine.capsHeld
        if output == .passWithCapsChord, type == .keyDown { chordFireCount += 1 }
        if output == .consumeAndToggleCapsLock { capsTapCount += 1 }

        let label: String
        switch event {
        case .capsDown: label = "Caps down"
        case .capsUp: label = "Caps up"
        case .otherKey: label = type == .keyDown ? "key ↓ \(keyCode)" : "key ↑ \(keyCode)"
        }
        record(label: label, keyCode: keyCode, verdict: verdictName(output))
        return output
    }

    private func verdictName(_ o: CapsMachine.Output) -> String {
        switch o {
        case .consume: "consumed"
        case .consumeAndToggleCapsLock: "CAPS TOGGLE"
        case .passUnmodified: "passed"
        case .passWithCapsChord: "chord+"
        }
    }

    private func record(label: String, keyCode: Int64, verdict: String) {
        events.append(EventRecord(time: .now, label: label, keyCode: keyCode, verdict: verdict))
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }

    func snapshot() -> (held: Bool, fires: Int, taps: Int, events: [EventRecord]) {
        lock.lock(); defer { lock.unlock() }
        return (capsHeldMirror, chordFireCount, capsTapCount, events)
    }

    func configure(tapToggles: Bool, threshold: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        machine.tapTogglesCapsLock = tapToggles
        machine.tapThreshold = threshold
    }
}

// MARK: - Controller

@MainActor
final class SpikeController: ObservableObject {
    static let shared = SpikeController()

    @Published var running = false
    @Published var trusted = false
    @Published var remapApplied = false
    @Published var tapActive = false
    @Published var includesShift = false
    @Published var capsHeld = false
    @Published var chordFires = 0
    @Published var capsTaps = 0
    @Published var capsLockOn = false
    @Published var tapTogglesCapsLock = true
    @Published var tapThreshold: TimeInterval = 0.3
    @Published var events: [EventRecord] = []
    @Published var lastError: String?

    private let state = TapState()
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func onLaunch() {
        installLifecycleObservers()
        refreshTrust()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pump() }
        }
    }

    func start() {
        refreshTrust()
        guard trusted else {
            lastError = "Accessibility not granted — grant it, then Start."
            return
        }
        applyFlags()
        do {
            try startTap()
            applyMachineConfig()
            try applyRemap()
            running = true
            lastError = nil
        } catch {
            stop()
            lastError = error.localizedDescription
        }
    }

    func stop() {
        stopTap()
        clearRemap()
        running = false
    }

    func toggleShift(_ on: Bool) {
        includesShift = on
        applyFlags()
    }

    func setTapToggles(_ on: Bool) {
        tapTogglesCapsLock = on
        applyMachineConfig()
    }

    func setTapThreshold(_ seconds: TimeInterval) {
        tapThreshold = seconds
        applyMachineConfig()
    }

    private func applyMachineConfig() {
        state.configure(tapToggles: tapTogglesCapsLock, threshold: tapThreshold)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    func refreshTrust() {
        trusted = AXIsProcessTrusted()
    }

    func promptTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true]
        trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    private func pump() {
        let snap = state.snapshot()
        capsHeld = snap.held
        chordFires = snap.fires
        capsTaps = snap.taps
        capsLockOn = CapsLockState.isOn()
        events = snap.events.reversed()
        remapApplied = state.tap != nil ? CapsLockHIDRemap.isApplied() : remapApplied
    }

    private func applyFlags() {
        state.lock.lock()
        state.capsFlags = includesShift
            ? [.maskControl, .maskAlternate, .maskCommand, .maskShift]
            : [.maskControl, .maskAlternate, .maskCommand]
        state.lock.unlock()
    }

    private func applyRemap() throws {
        try CapsLockHIDRemap.apply()
        remapApplied = true
    }

    private func clearRemap() {
        try? CapsLockHIDRemap.clear()
        remapApplied = false
    }

    private func startTap() throws {
        state.lock.lock()
        state.machine = CapsMachine()
        state.lock.unlock()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(state).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let state = Unmanaged<TapState>.fromOpaque(userInfo).takeUnretainedValue()
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    switch state.process(type: type, keyCode: keyCode) {
                    case .consume:
                        return nil
                    case .consumeAndToggleCapsLock:
                        CapsLockState.toggle()
                        return nil
                    case .passUnmodified:
                        return Unmanaged.passUnretained(event)
                    case .passWithCapsChord:
                        state.lock.lock()
                        let flags = state.capsFlags
                        state.lock.unlock()
                        event.flags.formUnion(flags)
                        return Unmanaged.passUnretained(event)
                    }
                },
                userInfo: userInfo
            )
        else {
            throw NSError(
                domain: "CapsSpike", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't create the session event tap. Grant Accessibility."]
            )
        }

        state.lock.lock(); state.tap = tap; state.lock.unlock()
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapActive = true
    }

    private func stopTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        state.lock.lock()
        let tap = state.tap
        state.tap = nil
        state.machine = CapsMachine()
        state.lock.unlock()
        if let tap { CFMachPortInvalidate(tap) }
        tapActive = false
    }

    private func installLifecycleObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        let rearm: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.stopTap(); self.clearRemap()
                self.start()
            }
        }
        observers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: rearm))
        observers.append(ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: rearm))
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: rearm))
        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: rearm))
    }
}

// MARK: - UI

struct StatusDot: View {
    let ok: Bool
    let label: String
    var neutralWhenOff = false
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : (neutralWhenOff ? Color.secondary : Color.orange))
                .frame(width: 10, height: 10)
            Text(label).font(.system(.body, design: .rounded))
            Spacer()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var c: SpikeController
    @State private var scratch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CapsSpike")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text("Standalone proof that Caps Lock can be a shortcut modifier with Accessibility only.")
                .foregroundStyle(.secondary)

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 8) {
                    StatusDot(ok: c.trusted, label: c.trusted
                        ? "Accessibility granted (the only grant needed)"
                        : "Accessibility NOT granted")
                    StatusDot(ok: c.tapActive, label: "Session event tap", neutralWhenOff: true)
                    StatusDot(ok: c.remapApplied, label: "Caps → F18 HID remap", neutralWhenOff: true)
                    StatusDot(ok: c.capsHeld, label: c.capsHeld ? "Caps HELD now" : "Caps not held",
                              neutralWhenOff: true)
                    StatusDot(ok: c.capsLockOn,
                              label: c.capsLockOn ? "CAPS LOCK is ON (LED lit)" : "Caps Lock off",
                              neutralWhenOff: true)
                    HStack {
                        Text("Chord fired").font(.system(.body, design: .rounded))
                        Spacer()
                        Text("\(c.chordFires)").monospacedDigit().bold()
                    }
                    HStack {
                        Text("Caps tap → toggle").font(.system(.body, design: .rounded))
                        Spacer()
                        Text("\(c.capsTaps)").monospacedDigit().bold()
                    }
                    if let err = c.lastError {
                        Text(err).font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(6)
            }

            HStack(spacing: 12) {
                Button(c.running ? "Stop" : "Start") {
                    c.running ? c.stop() : c.start()
                }
                .keyboardShortcut(.defaultAction)
                Toggle("Include ⇧ (⌃⌥⌘⇧)", isOn: Binding(
                    get: { c.includesShift }, set: { c.toggleShift($0) }
                ))
                Spacer()
                if !c.trusted {
                    Button("Grant Accessibility…") { c.promptTrust(); c.openAccessibilitySettings() }
                }
                Button("Re-check") { c.refreshTrust() }
            }

            GroupBox("Dual-role Caps") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Tap Caps alone → real Caps Lock toggle", isOn: Binding(
                        get: { c.tapTogglesCapsLock }, set: { c.setTapToggles($0) }
                    ))
                    HStack {
                        Text("Tap must be under")
                        Slider(
                            value: Binding(
                                get: { c.tapThreshold }, set: { c.setTapThreshold($0) }
                            ),
                            in: 0.15...0.6, step: 0.05
                        )
                        .frame(width: 160)
                        Text("\(Int(c.tapThreshold * 1000)) ms").monospacedDigit()
                    }
                    .font(.callout)
                }
                .padding(6)
            }

            GroupBox("Type here to test (hold Caps + a letter — it should NOT capitalize)") {
                TextField("scratch", text: $scratch, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2, reservesSpace: true)
            }

            GroupBox("Live events (newest first)") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(c.events) { e in
                            HStack {
                                Text(e.label).frame(width: 130, alignment: .leading)
                                Text(e.verdict).foregroundStyle(verdictColor(e.verdict))
                                    .frame(width: 90, alignment: .leading)
                                Spacer()
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { c.refreshTrust() }
    }

    private func verdictColor(_ v: String) -> Color {
        switch v {
        case "chord+": .green
        case "CAPS TOGGLE": .orange
        case "consumed": .blue
        case "rearm": .purple
        default: .secondary
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SpikeController.shared.onLaunch()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        SpikeController.shared.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CapsSpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("CapsSpike") {
            ContentView().environmentObject(SpikeController.shared)
        }
        .windowResizability(.contentSize)
    }
}
