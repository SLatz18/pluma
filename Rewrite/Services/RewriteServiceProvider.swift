import AppKit
import Foundation

final class RewriteServiceProvider: NSObject {
    @objc(rewriteSelection:userData:error:)
    func rewriteSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard
            let source = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !source.isEmpty
        else {
            errorPointer.pointee = RewriteEngineError.emptySelection.localizedDescription as NSString
            return
        }

        let defaults = UserDefaults.standard
        let provider = Preferences.provider(from: defaults)
        let intent = Preferences.intent(from: defaults)
        let ollamaModel = Preferences.ollamaModel(from: defaults)
        let resultBox = LockedResultBox<Result<String, Error>>()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            do {
                let output = try await RewriteRunner.rewrite(
                    provider: provider,
                    intent: intent,
                    text: source,
                    ollamaModel: ollamaModel
                )
                resultBox.store(.success(output))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 55) == .success else {
            errorPointer.pointee = RewriteEngineError.serviceTimedOut.localizedDescription as NSString
            return
        }

        guard let result = resultBox.load() else {
            errorPointer.pointee = RewriteEngineError.invalidResponse.localizedDescription as NSString
            return
        }

        switch result {
        case .success(let output):
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
        case .failure(let error):
            errorPointer.pointee = error.localizedDescription as NSString
        }
    }
}

private final class LockedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func store(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
