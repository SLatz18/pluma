# Harden Ollama loopback and local-model handling

Suggested labels: `security`, `privacy`, `ollama`  
Priority: High

## Summary

Ensure Rewrite sends user text only to the expected Ollama process on
`http://127.0.0.1:11434`, rejects redirects, excludes cloud-backed models, and
validates structured API responses before replacing user content.

## Value

Ollama can expose cloud-backed models through its local API. A loopback URL
alone therefore does not prove local inference. Redirect following can also
move a request away from loopback. Fail-closed checks are necessary if Rewrite
claims that Ollama text remains on the Mac.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `LoopbackPolicy` in `Rewrite/Providers/OllamaEngine.swift`
- `Model.isStoredLocally`
- `LoopbackOnlyRedirectDelegate`
- Deterministic rewrite request options
- `RewriteTests/OllamaEngineTests.swift`
- Source commits: `012faea`, `52f6e6b`, and `c5682d1`

Useful local-model evidence currently includes:

- positive model size;
- nonempty digest;
- nonempty model format;
- no `remote_model` or `remote_host`;
- no cloud-style model suffix/name.

## Required implementation for `main`

1. Use a dedicated `URLSession` configured with the redirect-blocking delegate.
2. Validate the request URL before sending and the final response URL before
   decoding.
3. Permit only HTTP, host `127.0.0.1`, and port `11434`. Decide explicitly
   whether `localhost` or IPv6 loopback should be supported; do not accept them
   accidentally.
4. Decode `/api/tags` and return only models with positive local evidence and
   no remote metadata.
5. Re-check the selected model before every rewrite that carries user text.
6. Apply the same origin/redirect policy to autocomplete and other Ollama
   paths, not only rewriting.
7. Decode non-2xx Ollama error bodies into actionable errors without exposing
   arbitrary response content.
8. Keep rewrite generation deterministic where appropriate. Autocomplete may
   retain separate sampling and token limits.
9. Parse rewrite responses through the shared framed-response parser.
10. Map connection failures, no-model state, cloud-model rejection, timeout,
    server errors, and malformed output distinctly.

## Acceptance criteria

- Requests cannot target a non-loopback scheme, host, or port.
- All HTTP redirects are rejected.
- Cloud-backed or ambiguously identified models are not listed or invoked.
- A model removed or changed after discovery is rejected at invocation time.
- Rewrite and autocomplete use the same network-origin policy.
- Ollama errors produce actionable UI messages.
- Valid local models continue to work.
- Privacy documentation exactly matches the implemented policy.

## Tests

Use a custom `URLProtocol` or local test server to cover:

- local and remote model metadata;
- malformed `/api/tags` data;
- cloud naming variants;
- redirects to loopback and non-loopback destinations;
- a final response URL that violates policy;
- Ollama JSON error bodies;
- empty/malformed chat responses;
- framed rewrite, unchanged, and refusal responses;
- deterministic rewrite request options;
- autocomplete-specific options.

## Dependencies

- `09-frame-and-parse-rewrite-responses.md`
- `06-enforce-operation-timeouts.md`

## Do not copy as-is

The rebased `OllamaEngine.swift` contains undefined methods and variables,
mismatched request-option types, and a response validator that references data
it does not receive. Its redirect delegate is defined but not attached, while
the completion path uses `URLSession.shared`. Specifically, `perform`,
`decodeModels(from:)`, and `decodeRewrite(from:original:)` are missing;
`rewrite()` and `makeChatRequestBody` disagree about `intent` versus
`directive`; and `ChatRequest.Options` has no `seed` field despite callers and
tests expecting one. Reimplement the design cleanly against current `main`.
