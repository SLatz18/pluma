import Foundation

struct TextEnvelope: Equatable, Sendable {
    let prefix: String
    let body: String
    let suffix: String

    init?(_ text: String) {
        guard
            let bodyStart = text.firstIndex(where: { !$0.isWhitespace }),
            let bodyEnd = text.lastIndex(where: { !$0.isWhitespace })
        else {
            return nil
        }

        prefix = String(text[..<bodyStart])
        body = String(text[bodyStart...bodyEnd])
        suffix = String(text[text.index(after: bodyEnd)...])
    }

    func replacingBody(with replacement: String) throws -> String {
        prefix + (try RewriteRunner.validatedOutput(replacement)) + suffix
    }
}
