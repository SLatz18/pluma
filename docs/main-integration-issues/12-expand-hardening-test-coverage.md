# Expand provider, Service, and data-integrity test coverage

Suggested labels: `tests`, `quality`, `providers`  
Priority: High

## Summary

Add deterministic unit and integration-style tests for provider decoding,
prompt parsing, recipe-chain behavior, Service rollback, preferences, timeout
policy, and rewrite concurrency.

## Value

The most important hardening behavior occurs at failure boundaries: malformed
model output, remote model metadata, clipboard write failure, timeout, and
stale async completion. These paths are difficult to validate manually and are
easy to regress during provider or UI refactors.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `RewriteTests/OllamaEngineTests.swift`
- `RewriteTests/PasteboardSnapshotTests.swift`
- `RewriteTests/PreferencesTests.swift`
- `RewriteTests/PromptComposerTests.swift`
- `RewriteTests/RewriteRunnerTests.swift`
- `RewriteTests/RewriteServiceProviderTests.swift`
- `RewriteTests/TextEnvelopeTests.swift`
- Source commits: `012faea`, `d26b2c6`, `52f6e6b`, and `c5682d1`

The helper-level `TextEnvelope`, `PasteboardSnapshot`, and preferences tests are
the best direct starting points.

## Required implementation for `main`

1. Port helper tests after their production APIs are integrated.
2. Update tests to use `main`'s ordered recipe-chain model rather than the
   removed single-intent API.
3. Introduce narrow injection seams for:
   - model/session responses;
   - Ollama transport;
   - chain step execution;
   - timeout clocks or controlled sleeping;
   - pasteboard writing.
4. Avoid live Apple Intelligence, Ollama, OpenAI, network, or permission
   dependencies in unit tests.
5. Cover behavior, not private implementation details.
6. Ensure XcodeGen discovers all test files and the generated project includes
   them in the test target.

## Required coverage

### Prompt and providers

- boundary framing and strict response parsing;
- Apple error/refusal mapping;
- Ollama local/remote model filtering;
- redirect/origin policy;
- success, server-error, malformed, empty, unchanged, and refusal responses.

### Recipe chains and concurrency

- ordered output flow across multiple recipes;
- stop-on-first-error behavior;
- progress events;
- timeout and cancellation;
- stale result/progress suppression.

### Service and clipboard

- success with preserved boundary whitespace;
- provider failure and timeout preserving pasteboard data;
- rich/custom pasteboard representation restoration;
- failed replacement rollback;
- empty selection and empty chain.

### Preferences and UI model

- provider/model/chain persistence and migration;
- provider status races;
- `canRewrite` state;
- reset/clear behavior where exposed.

## Acceptance criteria

- All tests compile against current production APIs.
- Tests require no installed model, Ollama daemon, network, or TCC permission.
- Failure-path tests are deterministic and do not depend on tight wall-clock
  timing.
- New tests run in the normal `Rewrite` scheme.
- CI runs the complete suite.
- No test silently falls through to a live provider.

## Verification

```sh
./scripts/bootstrap.sh
xcodebuild \
  -project Rewrite.xcodeproj \
  -scheme Rewrite \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  test
```

Run the suite from a clean environment with Ollama stopped and without relying
on Apple Intelligence availability.

## Dependencies

Implement alongside the feature briefs rather than waiting until the end:

- `04-preserve-pasteboard-contents.md`
- `05-preserve-rewrite-boundary-whitespace.md`
- `06-enforce-operation-timeouts.md`
- `07-harden-ollama-loopback-and-local-models.md`
- `08-harden-apple-intelligence-output-and-errors.md`
- `09-frame-and-parse-rewrite-responses.md`
- `10-prevent-stale-rewrite-results.md`

## Do not copy as-is

Several source-branch tests call missing helpers, expect obsolete prompt
delimiters, or inject a rewrite closure that the rebased Service provider
ignores. `PreferencesTests` still exercises the removed `intentKey` /
`intent(from:)` API, and `RewriteServiceProviderTests` seeds `intentKey`
instead of saving a recipe chain. Adapt each test to the final production API
and confirm it would fail if the protected behavior regressed.
