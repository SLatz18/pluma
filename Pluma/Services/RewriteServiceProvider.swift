import AppKit
import Foundation

final class RewriteServiceProvider: NSObject {
    // One chain step. Injectable so the Service flow is testable without a
    // live model: the real closure below is the only thing that touches one.
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
                ollamaModel: ollamaModel
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

        // TextEnvelope splits the selection into prefix / body / suffix, so the
        // model only ever sees the body and the writer's own indentation and
        // trailing newlines survive the round trip. A selection that is all
        // whitespace has no body, so the initializer fails and we bail.
        guard
            let source = pasteboard.string(forType: .string),
            let envelope = TextEnvelope(source)
        else {
            errorPointer.pointee = RewriteEngineError.emptySelection.localizedDescription as NSString
            return
        }

        // A Service entry can pin its action via NSUserData, so "Shorten" in the
        // Services menu always shortens instead of running whatever the app
        // happens to have selected. Without it we fall back to the saved chain.
        let chain = Self.chain(forUserData: userData, defaults: defaults)
        guard !chain.isEmpty else {
            errorPointer.pointee = RewriteEngineError.emptyChain.localizedDescription as NSString
            return
        }

        // Captured before any write so a partial failure can put the writer's
        // clipboard back exactly as it was, including non-string flavors.
        let originalSnapshot = PasteboardSnapshot(pasteboard)

        let provider = Preferences.provider(from: defaults)
        let ollamaModel = Preferences.ollamaModel(from: defaults)
        let body = envelope.body
        let resultBox = LockedResultBox<Result<String, Error>>()
        let semaphore = DispatchSemaphore(value: 0)
        let run = rewriteOperation

        let worker = Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            do {
                // Nonisolated chain: the semaphore below blocks this thread,
                // so hopping to the main actor here would deadlock.
                var output = body
                for intent in chain {
                    try Task.checkCancellation()
                    output = try await run(provider, intent, output, ollamaModel)
                }
                resultBox.store(.success(try envelope.replacingBody(with: output)))
            } catch {
                resultBox.store(.failure(error))
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            // Stop the model work; AppKit gives a Service ~30s before it is
            // considered hung, so we surface a timeout well inside that.
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

    // NSUserData is a plain string in Info.plist. "selectedAction" is the
    // sentinel meaning "use whatever the app has selected"; any RewriteIntent
    // raw value pins that single action instead.
    static func chain(
        forUserData userData: String?,
        defaults: UserDefaults
    ) -> [RewriteIntent] {
        if
            let userData,
            userData != "selectedAction",
            let pinned = RewriteIntent(rawValue: userData)
        {
            return [pinned]
        }
        return Preferences.chain(from: defaults)
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
