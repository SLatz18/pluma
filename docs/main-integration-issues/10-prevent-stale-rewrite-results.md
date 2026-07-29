# Prevent stale rewrite and provider-status results

Suggested labels: `bug`, `concurrency`, `swiftui`  
Priority: High

## Summary

Make rewrite and provider-status operations identity-aware so a result cannot
update the UI after the user changes the input, recipe chain, provider, model,
or starts a newer request.

## Value

Model operations are asynchronous. Without request identity and captured
configuration, a slow old request can overwrite newer text or report status
for a provider the user has already changed. This is especially risky when the
result can be copied or applied to another app.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `statusRefreshID` and `activeRewriteID` concepts in
  `Rewrite/Services/RewriteViewModel.swift`
- `canRewrite`
- stale provider/model checks
- clipboard-write failure surfacing
- Source commits: `012faea`, `d26b2c6`, and `52f6e6b`

The rebased implementation is incomplete: it references a missing
`invalidateActiveRewrite()`, compares removed `selectedIntent` state instead of
the recipe chain, uses an undefined `rawOutput`, references an undeclared
`clipboardWriteFailed` error, and leaves an obsolete `intentBinding` in
`SettingsView`. Its `canRewrite` value also omits the empty-chain check that the
playground currently performs separately.

## Required implementation for `main`

1. Assign a unique ID to every status refresh and rewrite.
2. Capture an immutable request configuration containing:
   - source text;
   - provider;
   - selected Ollama model;
   - the complete ordered recipe chain.
3. Before applying progress, success, or failure, confirm the request is still
   active and the relevant configuration has not changed.
4. Invalidate and, where possible, cancel active work when:
   - provider changes;
   - Ollama model changes;
   - the recipe chain changes;
   - input changes or output is promoted to input;
   - a newer rewrite begins.
5. Keep `isRewriting`, `activeRewriteID`, output, and error state internally
   consistent on success, error, cancellation, and invalidation.
6. Ensure progress from an old chain cannot appear in a newer chain's output.
7. Derive `canRewrite` from provider readiness, nonempty chain, valid body text,
   and no active request; use it in the playground UI.
8. Keep all UI state updates on `MainActor`.

## Acceptance criteria

- Changing input during a rewrite prevents the old result from appearing.
- Changing provider, model, or chain invalidates the old request.
- A slow status result cannot overwrite the status of the newly selected
  provider.
- Only one active rewrite owns progress/output state.
- Cancellation clears loading state without displaying a misleading error.
- `canRewrite` includes nonempty-chain validation, matches all actual rewrite
  preconditions, and controls the run button.
- Swift 6 strict-concurrency checks pass.

## Tests

Inject controllable async provider and chain runners to test:

- two rewrites completing out of order;
- provider/model/chain changes while work is pending;
- stale progress callbacks;
- cancellation and thrown errors;
- status refreshes completing out of order;
- `canRewrite` for whitespace-only input, empty chains, unavailable providers,
  and active requests.

## Dependencies

- `06-enforce-operation-timeouts.md`
- `05-preserve-rewrite-boundary-whitespace.md`

## Do not copy as-is

Adapt the request-ID concept to `main`'s ordered recipe chain rather than
copying the rebased view model or its stale `SettingsView` binding.
