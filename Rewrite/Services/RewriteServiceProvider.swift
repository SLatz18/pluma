import AppKit
import Foundation

final class RewriteServiceProvider: NSObject {
    typealias RewriteOperation = @Sendable (
        RewriteProviderChoice,
        RewriteIntent,
        String,
        String
    ) async throws -> String

    private let defaults: UserDefaults
    private let timeout: TimeInterval
    private let rewriteOperation: RewriteOperation

    init(
        defaults: UserDefaults = .standard,
        timeout: TimeInterval = RewriteTimeouts.service,
        rewriteOperation: @escaping RewriteOperation = { provider, intent, text, ollamaModel in
            try await RewriteRunner.rewrite(
                provider: provider,
                intent: intent,
                text: text,
                ollamaModel: ollamaModel,
                timeout: RewriteTimeouts.serviceRequest
            )
        }
    ) {
        self.defaults = defaults
        self.timeout = timeout
        self.rewriteOperation = rewriteOperation
        super.init()
    }

    @objc(rewriteSelection:userData:error:)
    func rewriteSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        errorPointer.pointee = nil

        guard
            let source = pasteboard.string(forType: .string),
            let envelope = TextEnvelope(source)
        else {
            errorPointer.pointee = RewriteEngineError.emptySelection.localizedDescription as NSString
            return
        }
        let originalSnapshot = PasteboardSnapshot(pasteboard)

        let provider = Preferences.provider(from: defaults)
        let chain = Preferences.chain(from: defaults)
        let ollamaModel = Preferences.ollamaModel(from: defaults)
        let resultBox = LockedResultBox<Result<String, Error>>()
        let semaphore = DispatchSemaphore(value: 0)

        let worker = Task.detached(priority: .userInitiated) { [rewriteOperation] in
            defer { semaphore.signal() }
            do {
                // Nonisolated chain: the semaphore below blocks this thread,
                // so hopping to the main actor here would deadlock.
                let output = try await RewriteRunner.rewriteChain(
                    provider: provider,
                    steps: chain,
                    text: source,
                    ollamaModel: ollamaModel
                )
                let output = try envelope.replacingBody(with: rawOutput)
                resultBox.store(.success(output))
            } catch {
                resultBox.store(.failure(error))
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            worker.cancel()
            errorPointer.pointee = RewriteEngineError.serviceTimedOut.localizedDescription as NSString
            return
        }

        guard let result = resultBox.load() else {
            errorPointer.pointee = RewriteEngineError.invalidResponse.localizedDescription as NSString
            return
        }

        switch result {
        case .success(let output):
            guard PasteboardSnapshot.replaceString(
                output,
                on: pasteboard,
                rollbackTo: originalSnapshot
            ) else {
                errorPointer.pointee = RewriteEngineError.invalidResponse.localizedDescription as NSString
                return
            }
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
