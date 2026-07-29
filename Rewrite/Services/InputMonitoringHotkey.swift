import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Global hotkey listener backed by Input Monitoring and CGEventTap.
/// Fires before the frontmost app consumes the key, unlike Carbon hotkeys.
final class InputMonitoringHotkey: @unchecked Sendable {
    static let shared = InputMonitoringHotkey()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?

    private init() {}

    var isActive: Bool { eventTap != nil }

    func start(handler: @escaping @MainActor () -> Void) {
        stop()
        self.handler = handler

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: Self.callback,
                userInfo: userInfo
            )
        else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard type == .keyDown, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<InputMonitoringHotkey>.fromOpaque(userInfo).takeUnretainedValue()
        guard monitor.matchesHotkey(event) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor in
            monitor.handler?()
        }
        return Unmanaged.passUnretained(event)
    }

    private func matchesHotkey(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_E) else {
            return false
        }

        let flags = event.flags.intersection(.deviceIndependentFlagsMask)
        let required: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        return flags.contains(required)
    }
}
