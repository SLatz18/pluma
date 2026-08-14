import Foundation
import IOKit
import IOKit.hidsystem

/// Reads and writes the real Caps Lock state, LED included.
///
/// Once Caps is aliased to F18 the OS never toggles caps for us, and synthetic
/// Caps key events don't set the state either (issue #23, wall 2). Driving
/// IOHIDSystem directly is the only mechanism that works, and it is what keeps
/// a lone Caps tap behaving like Caps Lock.
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

    /// Clears caps on teardown so disabling the feature never strands the key on.
    static func turnOff() {
        _ = withConnection { handle in
            IOHIDSetModifierLockState(handle, Int32(kIOHIDCapsLockState), false)
        }
    }
}
