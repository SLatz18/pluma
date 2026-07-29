# Preserve leading and trailing whitespace during rewrites

Suggested labels: `bug`, `text-processing`, `services`
Priority: High

## Summary

Separate a selection's boundary whitespace from its editable body, send only
the body through the recipe chain, and reattach the original prefix and suffix
to the final validated output.

## Value

Selected text often includes indentation, blank lines, list spacing, or a
trailing newline. Models frequently trim or normalize those boundaries.
Preserving them prevents a rewrite from damaging surrounding document layout
and makes Service and playground behavior predictable.

Current `main` also strips boundaries before the model runs:
`RewriteServiceProvider` and `SelectionRewriteController` call
`trimmingCharacters(in: .whitespacesAndNewlines)` on selected text. This issue
must replace that behavior on both the Service and global-hotkey paths.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/Services/TextEnvelope.swift`
- `RewriteTests/TextEnvelopeTests.swift`
- Source commit: `d26b2c6`

The existing `TextEnvelope`:

- rejects whitespace-only input;
- captures `prefix`, `body`, and `suffix`;
- validates and inserts a replacement body.

Its core shape is reusable:

```swift
struct TextEnvelope: Equatable, Sendable {
    let prefix: String
    let body: String
    let suffix: String

    init?(_ text: String) { /* split at first/last non-whitespace */ }

    func replacingBody(with replacement: String) throws -> String {
        prefix + (try RewriteRunner.validatedOutput(replacement)) + suffix
    }
}
```

## Required implementation for `main`

1. Port `TextEnvelope` and its focused unit tests.
2. In the Service, build an envelope from the selected string.
3. Run the entire recipe chain using `envelope.body`, not the original full
   selection.
4. Apply `envelope.replacingBody(with:)` only after the final recipe step.
5. In the playground, preserve boundaries for the final output while deciding
   whether intermediate progress should display body-only or reconstructed
   text.
6. Apply the same behavior to Accessibility-based selection rewriting if the
   selected AX text can include boundary whitespace.
7. Keep dictation cleanup separate: a transcript is not a document selection
   and may intentionally normalize boundaries.

## Acceptance criteria

- Leading spaces and tabs are byte-for-byte preserved.
- Trailing spaces and newlines are byte-for-byte preserved.
- Multiline indentation outside the rewritten body remains unchanged.
- Whitespace-only input is rejected without invoking a model.
- Each recipe step receives only the current body.
- Final output contains exactly one copy of the original prefix and suffix.
- Service, playground, and selection-hotkey behavior are consistent where
  applicable.

## Tests

Cover:

- no boundary whitespace;
- spaces, tabs, and mixed newlines;
- whitespace-only input;
- Unicode whitespace;
- a multi-step chain proving boundaries are not passed through each model;
- unchanged/model-refusal output;
- invalid empty model output.

## Dependencies

- `09-frame-and-parse-rewrite-responses.md`
- `04-preserve-pasteboard-contents.md`

## Do not copy as-is

The source branch's Service and view model create an envelope but still pass
the full source through `rewriteChain`, then reference an undefined
`rawOutput`. Port `TextEnvelope`; rewrite the call sites for current `main`.
