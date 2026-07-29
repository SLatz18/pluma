# Preserve pasteboard contents during Service rewrites

Suggested labels: `bug`, `data-integrity`, `services`
Priority: High

## Summary

Snapshot all pasteboard items and representations before a macOS Service
rewrite, then perform rollback-safe replacement so a failed write cannot
destroy the user's clipboard contents.

## Value

An `NSPasteboard` item can contain plain text, rich text, HTML, file URLs, and
application-specific representations. Calling `clearContents()` before a
replacement is irreversible unless those representations were captured.
Clipboard loss is a high-impact data-integrity failure even when the rewrite
itself fails safely.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/Services/PasteboardSnapshot.swift`
- `RewriteTests/PasteboardSnapshotTests.swift`
- Integration in `Rewrite/Services/RewriteServiceProvider.swift`
- Integration in `Rewrite/Services/RewriteViewModel.swift`
- Source commit: `d26b2c6`

The helper captures each `NSPasteboardItem` as a dictionary from pasteboard
type to raw `Data`, reconstructs all items on restore, and provides a
`replaceString(_:on:rollbackTo:)` operation.

## Required implementation for `main`

1. Port `PasteboardSnapshot` as a standalone AppKit helper.
2. Before the Service starts asynchronous work, capture the complete input
   pasteboard.
3. On success, write the replacement as a new plain-text item.
4. If writing fails after clearing the pasteboard, restore the snapshot.
5. Return a specific clipboard-write error instead of reporting an unreadable
   model response.
6. Use the helper for the playground's explicit Copy action if that path clears
   or replaces the general pasteboard.
7. Keep selection rewriting through Accessibility separate; do not introduce a
   copy/paste fallback unless explicitly designed and tested.

## Acceptance criteria

- A successful Service rewrite returns the rewritten string.
- A provider error or timeout leaves the original Service pasteboard intact.
- A failed replacement restores every original item and representation,
  including non-string data.
- An empty original pasteboard can be restored.
- Clipboard-write failures surface a specific actionable error.
- The helper is safe under Swift 6 concurrency at its call sites.

## Tests

Add tests for:

- restoring multiple pasteboard items;
- restoring plain text plus a custom binary representation;
- successful replacement;
- rollback after simulated write failure;
- empty-pasteboard restoration;
- provider failure and timeout preserving Service input.

Where AppKit does not permit forcing `writeObjects` to fail, inject a small
pasteboard-writing abstraction so rollback can be tested deterministically.

## Dependencies

- Works closely with `05-preserve-rewrite-boundary-whitespace.md`.
- Service integration tests belong in
  `12-expand-hardening-test-coverage.md`.

## Do not copy as-is

The helper itself is a strong starting point, but the rebased
`RewriteServiceProvider` does not compile and ignores its injected rewrite
operation. It also maps a failed Service pasteboard write to `invalidResponse`,
while `RewriteViewModel.copyOutput()` references an undeclared
`clipboardWriteFailed` case. Port the helper, add a real clipboard-specific
error, and integrate it into `main`'s current chain-based Service implementation
rather than copying that provider file.
