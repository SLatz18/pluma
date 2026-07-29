# Add unit and integration coverage for clipboard fallback components

Suggested labels: `testing`, `quality`

## Summary

Add focused tests for the local algorithms and state transitions introduced by
the clipboard fallback:

- Word-level diff output and change counting.
- Duplicate hotkey suppression.
- Hotkey status metadata and tier transitions.
- Clipboard controller guards and Undo.
- Pasteboard error behavior.

## Value relative to `main`

These tests primarily protect new fallback behavior and do not materially test
`main`'s existing Accessibility rewrite, autocomplete, or dictation.

The word-diff and debounce tests are inexpensive and deterministic, so they
provide good regression value. Controller and pasteboard tests need small
dependency-injection changes to avoid touching the real clipboard or model.

## Reference implementation

Basic tests exist on branch `cloudai/finish-rewrite-e2e-5d52`:

- `RewriteTests/WordDifferTests.swift`
- `RewriteTests/HotkeyDebouncerTests.swift`
- `RewriteTests/HotkeyStatusTests.swift`

Those tests are a starting point. This issue should expand coverage to the
controller and pasteboard abstraction.

## Existing test code to port

```swift
final class WordDifferTests: XCTestCase {
    func testIdenticalTextProducesOnlyUnchangedSegments() {
        let segments = WordDiffer.diff(
            original: "hello world",
            revised: "hello world"
        )

        XCTAssertTrue(
            segments.allSatisfy { $0.kind == .unchanged }
        )
        XCTAssertEqual(WordDiffer.changeCount(segments), 0)
    }

    func testSingleWordReplacement() {
        let segments = WordDiffer.diff(
            original: "hello world",
            revised: "hello there"
        )

        XCTAssertEqual(
            segments.map(\.kind),
            [.unchanged, .removed, .added]
        )
        XCTAssertEqual(
            segments.map(\.text),
            ["hello", "world", "there"]
        )
        XCTAssertEqual(WordDiffer.changeCount(segments), 1)
    }
}
```

```swift
final class HotkeyDebouncerTests: XCTestCase {
    func testFirstCallAlwaysFires() {
        var debouncer = HotkeyDebouncer(interval: 0.35)
        XCTAssertTrue(debouncer.shouldFire())
    }

    func testSecondCallWithinIntervalIsIgnored() {
        var debouncer = HotkeyDebouncer(interval: 0.35)
        XCTAssertTrue(debouncer.shouldFire())
        XCTAssertFalse(debouncer.shouldFire())
    }
}
```

The debouncer should accept an injected clock before adding time-dependent
expiry tests:

```swift
struct HotkeyDebouncer {
    private var lastFire: Date?
    let interval: TimeInterval
    var now: () -> Date = Date.init

    mutating func shouldFire() -> Bool {
        let current = now()
        if let lastFire,
           current.timeIntervalSince(lastFire) < interval {
            return false
        }
        lastFire = current
        return true
    }
}
```

## Refactor for controller tests

Introduce protocols or closures around model execution, pasteboard access, and
HUD output:

```swift
protocol ClipboardTextStore {
    func readString() async throws -> String
    func writeString(_ value: String)
}

protocol ClipboardRewriteRunning {
    func rewrite(
        provider: RewriteProviderChoice,
        intent: RewriteIntent,
        text: String,
        ollamaModel: String
    ) async throws -> String
}

@MainActor
protocol ClipboardHUDPresenting {
    func showResult(
        original: String,
        revised: String,
        intent: RewriteIntent
    )
    func showHint(_ message: String)
}
```

Production adapters can delegate to `PasteboardAccess`, `RewriteRunner`, and
`HUDWindowController`. Tests can use in-memory fakes.

## Required test matrix

### WordDiffer

- Empty → empty.
- Empty → words.
- Words → empty.
- Identical input.
- Single insertion.
- Single deletion.
- Single replacement.
- Multiple separated change runs.
- Whitespace and line-break normalization.
- Punctuation behavior is documented.
- A reasonable upper-bound performance test.

Avoid reverse strides starting from `count - 1`; empty arrays must be safe.
Prefer:

```swift
for i in old.indices.reversed() {
    for j in new.indices.reversed() {
        // Build LCS table.
    }
}
```

### HotkeyDebouncer

- First fire accepted.
- Immediate duplicate rejected.
- Fire after interval accepted using an injected clock.
- Boundary exactly equal to interval accepted.

### ClipboardRewriteController

- Empty and non-text input display a hint.
- Concurrent second invocation does not run.
- Previous result is not rewritten again.
- Model failure preserves clipboard.
- No-op response preserves clipboard and displays a hint.
- Success writes output and displays result.
- Undo restores original.
- Undo with no history is a no-op.

### PasteboardAccess

- Whitespace-only string is rejected.
- Missing plain-text type is rejected without reading payload.
- Denied access produces `accessDenied`.
- A write replaces clipboard text.

### Hotkey status

- Standard, Enhanced, and Unavailable metadata remains stable.
- Carbon registration failure produces Unavailable.
- Input Monitoring denial leaves Standard active.

## Acceptance criteria

- All deterministic tests pass without system permission prompts.
- Unit tests never read or mutate `NSPasteboard.general`.
- No test invokes Apple Intelligence or Ollama.
- Empty diff inputs cannot crash.
- Controller behavior is tested through injected fakes.
- Existing `main` tests remain green.

## Dependencies

- Implement after the relevant fallback components, or include the small
  dependency-injection refactor in the same PR.
