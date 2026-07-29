# Improve VoiceOver labels for rewrite controls

Suggested labels: `accessibility`, `ui`, `swiftui`  
Priority: Medium

## Summary

Add concise, state-aware accessibility labels to provider status, rewrite
errors, editable/result panels, and icon-only actions in the playground.

## Value

Several controls rely on icons, visual grouping, tooltips, or status colors.
VoiceOver users need equivalent names and state information without hearing
duplicated or excessively verbose content.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `Rewrite/Views/ProviderMenu.swift`
- `Rewrite/Views/RewritePlaygroundView.swift`
- Source commit: `012faea`

Existing additions include labels for:

- provider name, status, and status detail;
- rewrite failures;
- source/result editor regions;
- “Use result as original”;
- “Copy result”.

## Required implementation for `main`

1. Port the useful labels as small, reviewable SwiftUI changes.
2. Audit whether native controls already expose a sufficient label before
   overriding them.
3. Keep labels concise and avoid reading the entire rewritten result every time
   focus enters a large editor.
4. Expose changing provider/rewrite status as state or value where appropriate.
5. Ensure icon-only buttons have stable names independent of SF Symbol choice.
6. Group related decorative children without hiding interactive controls.
7. Review all three main pages—Rewrite, Autocomplete, and Dictation—for the same
   class of issue rather than limiting the audit to the playground.
8. Preserve Full Keyboard Access and visible focus behavior.

## Acceptance criteria

- Every icon-only actionable control has a meaningful accessibility label.
- Provider selection communicates provider and readiness state.
- Errors are announced with context.
- Source and result regions are distinguishable.
- Large result text is not redundantly spoken by both a container and editor.
- Labels do not duplicate native button or picker names.
- Rewrite, Autocomplete, and Dictation pages are usable with VoiceOver and Full
  Keyboard Access.

## Verification

- Navigate the complete app using VoiceOver only.
- Repeat with Full Keyboard Access enabled.
- Verify light/dark appearance and increased contrast do not remove state cues.
- Test empty, loading, success, and error states.
- Use Accessibility Inspector to check names, roles, values, and grouping.

## Dependencies

None for the small label changes. Coordinate state labels with
`10-prevent-stale-rewrite-results.md`.

## Do not copy as-is

Review the source branch's combined result-container label before copying it.
Reading `model.outputText` as the container label can cause large results to be
spoken redundantly when the editor already exposes its value.
