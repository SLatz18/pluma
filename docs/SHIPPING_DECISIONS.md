# Shipping decisions

Reviewed July 27, 2026. Recheck these sources before each major release.

## Cross-app editing

Rewrite ships a standard macOS Service. Apple documents Services as the
sandbox-compatible mechanism for receiving and returning selected text. The
default shortcut is intentionally limited to one core command, and the UI links
to Keyboard Settings so people can resolve conflicts or assign Hyperkey-E.

Rewrite does not use Carbon `RegisterEventHotKey`. Apple Developer Technical
Support describes it as legacy and cannot recommend it. The modern global-event
alternative requires Input Monitoring, which is unnecessary for this app’s core
job.

- [Services properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)
- [Apple DTS: global hotkeys on macOS](https://developer.apple.com/forums/thread/735223)

## Apple Intelligence

- Check `SystemLanguageModel.availability` and keep Ollama as a fallback.
- Create a new `LanguageModelSession` for each single-turn rewrite.
- Use nonstreaming `respond` for background Service requests.
- Use greedy sampling for stable editing results.
- Use `permissiveContentTransformations`, which Apple explicitly provides for
  rewrite and summarization.
- Map context-window, unavailable-asset, rate-limit, and refusal errors to
  actionable messages.
- Follow Apple’s Foundation Models acceptable-use requirements.

- [Generating content with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Improving model-output safety](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
- [Foundation Models acceptable-use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)

## Ollama

Ollama supports cloud-backed models through the same loopback API used for
local models. Rewrite requires `/api/tags` to report a positive file size,
digest, and model format before listing or invoking a model. It also blocks
redirects away from loopback. Requests use nonstreaming responses plus a fixed
seed and zero temperature.

- [Ollama cloud models](https://docs.ollama.com/cloud)
- [Ollama model list API](https://docs.ollama.com/api/tags)
- [Ollama chat API](https://docs.ollama.com/api/chat)

## Privacy and release validation

Rewrite reads selected text only after an explicit Service or playground
action, stores no text, and contains no analytics SDK. The bundled privacy
manifest reports no collection or tracking and declares app-only
`UserDefaults` usage with reason `CA92.1`. CI validates the manifest, sandbox
entitlements, Service declaration, Release build, and packaged resources.

- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
