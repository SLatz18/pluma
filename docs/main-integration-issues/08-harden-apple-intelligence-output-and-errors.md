# Harden Apple Intelligence output and error handling

Suggested labels: `apple-intelligence`, `reliability`, `privacy`
Priority: High

## Summary

Make Apple Intelligence rewriting deterministic, validate its framed output,
map Foundation Models failures to actionable app errors, and prevent refusal or
safety text from replacing the user's selection.

## Value

Foundation Models can be unavailable, downloading, rate limited, over its
context window, or unwilling to perform a request. Treating every response as
replacement text risks inserting tags, explanations, or refusal messages into
the user's document.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `RefusalClassification` in
  `Rewrite/Providers/AppleIntelligenceEngine.swift`
- Expanded cases in `Rewrite/Providers/RewriteEngineError.swift`
- `PromptComposer.looksLikeRefusal`
- Source commit: `c5682d1`

The existing engine already uses:

- `SystemLanguageModel.availability`;
- a new `LanguageModelSession` per rewrite;
- `.permissiveContentTransformations`;
- a guided refusal-classification type.

## Required implementation for `main`

1. Keep the availability check and per-request session.
2. Use greedy sampling for deterministic editing output.
3. Parse every rewrite through the shared framed-response parser.
4. Treat `<unchanged/>` as a successful no-op, preserving the original text.
5. Map Foundation Models errors, including:
   - context-window exhaustion;
   - unavailable assets/model state;
   - rate limiting/busy state;
   - refusal;
   - other generation failures.
6. Detect obvious lexical refusals before replacement.
7. Decide whether the second guided refusal-classification call is justified
   for ambiguous output. If retained:
   - call it only after structured parsing;
   - avoid classifying an unchanged original as a new refusal;
   - apply a timeout;
   - test latency and false positives.
8. Ensure autocomplete remains on its completion-specific prompt and sampling
   path; rewrite framing must not leak into ghost-text output.

## Acceptance criteria

- A normal rewrite returns only edited text, never response tags.
- `<unchanged/>` leaves the user's original text unchanged.
- Empty, unstructured, or malformed output is rejected.
- A refusal never replaces selected text.
- Context, availability, rate-limit, and general generation failures show
  distinct actionable messages.
- Rewrites are deterministic for the same model/input where the framework
  allows.
- Autocomplete behavior and latency are not regressed.

## Tests

Model `LanguageModelSession` behind a narrow protocol or injectable closure so
tests can simulate:

- framed rewrite and unchanged responses;
- malformed and empty responses;
- lexical and guided refusals;
- each mapped `GenerationError`;
- cancellation/timeout;
- original source text that itself contains refusal-like language.

Keep prompt/parser tests independent from live Apple Intelligence availability.

## Dependencies

- `09-frame-and-parse-rewrite-responses.md`
- `06-enforce-operation-timeouts.md`

## Do not copy as-is

The source branch adds `isRefusal(_:)`, but the rewrite path never calls it,
does not parse framed output, does not use greedy sampling there, and does not
map the new error cases. Port the intended behavior, not the dead helper alone.
