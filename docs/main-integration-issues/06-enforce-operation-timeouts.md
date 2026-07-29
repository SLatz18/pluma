# Enforce operation-specific rewrite timeouts

Suggested labels: `reliability`, `concurrency`, `services`
Priority: High

## Summary

Centralize timeout policy and enforce real cancellation/deadlines for Ollama
discovery, interactive rewrites, autocomplete, dictation cleanup, and macOS
Service requests.

## Value

Network and model APIs can stall. The macOS Service has a strict user-facing
budget, while interactive in-app work can wait longer. Explicit deadlines keep
the Service responsive, prevent orphan work, and provide consistent errors.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/Providers/RewriteTimeouts.swift`
- Timeout-related `RewriteEngineError` cases
- Service semaphore timeout in `RewriteServiceProvider`
- Source commits: `012faea` and `52f6e6b`

The proposed policy currently contains:

- Ollama discovery: 3 seconds
- general model request: 50 seconds
- Service model request: 20 seconds
- outer Service wait: 24 seconds

These values express useful intent but are not correctly enforced.
Current `main` instead waits up to 55 seconds in the Service provider while
`Info.plist` declares a 60,000 ms Service timeout. The final budgets should be
chosen together with the Service metadata issue rather than assuming either
branch's numbers are already correct.

## Required implementation for `main`

1. Define named budgets by operation, not one universal timeout.
2. Keep the inner Service request deadline shorter than the outer AppKit wait,
   and keep both below the declared Service timeout.
3. Apply URL request timeouts to Ollama discovery, rewrite, and completion.
4. Add an async timeout primitive for operations without a request-level
   timeout, using structured concurrency.
5. Cancel losing tasks and ensure continuations/URLSession tasks observe
   cancellation.
6. Thread the selected budget through `RewriteRunner` and chain execution.
7. Preserve dictation's raw-transcript fallback when cleanup times out.
8. Distinguish timeout errors from provider-unavailable and malformed-response
   errors.

A suitable helper may use `withThrowingTaskGroup`, racing work against
`Task.sleep`, while ensuring the operation itself is cancellation-aware.

## Acceptance criteria

- Ollama discovery fails within its configured budget.
- A Service rewrite's inner work stops before the outer Service deadline.
- AppKit receives a timeout error before the Service limit selected in
  `Info.plist`.
- In-app rewrite and autocomplete budgets can differ from Service budgets.
- A timed-out chain does not continue running later steps.
- Dictation inserts the raw transcript when cleanup times out.
- Timeout parameters are actually consumed; no public timeout argument is a
  no-op.

## Tests

- Inject a sleeping step runner and verify each deadline.
- Verify the losing timeout/work task is cancelled.
- Verify a multi-step chain stops after the timed-out step.
- Verify Service timeout leaves its pasteboard unchanged.
- Verify dictation timeout returns its documented fallback.

Use deterministic test durations with generous ordering margins rather than
asserting exact wall-clock milliseconds.

## Dependencies

- `12-expand-hardening-test-coverage.md`

Coordinate cancellation ownership with
`10-prevent-stale-rewrite-results.md`; neither issue needs to block the other.

## Do not copy as-is

The source branch adds a `timeout` argument to `RewriteRunner.rewrite` but never
uses it. Its 50-second model timeout can also outlive the 24-second Service
wait. Preserve the policy concept, not the current wiring.
