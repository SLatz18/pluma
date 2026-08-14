import Foundation

/// Restores the keyboard if Pluma dies without cleaning up.
///
/// The HID remap lives in the driver and outlives the process, so a crash or a
/// Force Quit would otherwise leave Caps aliased to an inert F18 until the next
/// launch or a reboot. `applicationWillTerminate` does not run for SIGKILL or a
/// crash, and a signal handler cannot safely spawn a process.
///
/// So we hand the cleanup to a child that cannot crash with us: `sh` blocks
/// reading a pipe whose write end only Pluma holds. Any death closes the pipe,
/// the read returns EOF, and the child restores the exact mapping that existed
/// before we touched it — not a blanket wipe.
@MainActor
enum CapsLockGuardian {
    private static var process: Process?
    private static var pipe: Pipe?

    /// - Parameter restoreJSON: the `UserKeyMapping` array to put back, encoded
    ///   as JSON. This is the user's mapping list *without* pluma's entry.
    static func arm(restoreJSON: String) {
        disarm()

        // JSON here is machine-generated from integers only, so it cannot
        // contain a single quote to break out of the shell literal.
        guard !restoreJSON.contains("'") else {
            DebugLog.log("caps guardian: refusing to arm, unexpected quote in mapping")
            return
        }

        let script = """
        cat > /dev/null; \
        /usr/bin/hidutil property --set '{"UserKeyMapping":\(restoreJSON)}' > /dev/null 2>&1
        """

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        let stdin = Pipe()
        child.standardInput = stdin
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
            // Retaining the write end is what keeps the child blocked; letting
            // it deallocate would fire the restore immediately.
            process = child
            pipe = stdin
            DebugLog.log("caps guardian: armed (pid \(child.processIdentifier))")
        } catch {
            DebugLog.log("caps guardian: failed to arm: \(error.localizedDescription)")
        }
    }

    /// Clean teardown path — Pluma is restoring the mapping itself, so the
    /// guardian must be retired before its saved snapshot goes stale.
    static func disarm() {
        guard let child = process else { return }
        // Terminate first: closing the pipe alone would let the child race us
        // and re-apply a snapshot that is no longer current.
        child.terminate()
        try? pipe?.fileHandleForWriting.close()
        process = nil
        pipe = nil
        DebugLog.log("caps guardian: disarmed")
    }

    static var isArmed: Bool { process?.isRunning ?? false }
}
