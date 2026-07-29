# Frame prompts and strictly parse rewrite responses

Suggested labels: `text-processing`, `security`, `providers`  
Priority: High

## Summary

Treat source text as untrusted data inside unique prompt boundaries and require
providers to return one of two machine-readable forms: a rewritten body or an
explicit unchanged result.

## Value

Source text may contain instructions, XML-like tags, or prose that resembles a
model response. Unique boundaries reduce prompt confusion, while strict
response parsing prevents commentary, labels, refusal text, or wrapper tags
from being inserted into a user's document.

## Existing implementation to reuse

Source branch: `cloudai/build-rewrite-app-bd38`

- `PromptComposer.systemInstructions`
- Boundary-based source framing
- `<rewrite>...</rewrite>` and `<unchanged/>` response contract
- `PromptComposer.looksLikeRefusal`
- `RewriteTests/PromptComposerTests.swift`
- Source commits: `52f6e6b`, `7e3fcfd`, and `c5682d1`

## Required implementation for `main`

1. Generate one unpredictable boundary per prompt and pass it explicitly into
   prompt construction.
2. Put only the editable source inside the boundary markers.
3. Require exactly:

   ```text
   <rewrite>
   edited text
   </rewrite>
   ```

   or:

   ```text
   <unchanged/>
   ```

4. Implement a shared parser that:
   - trims only wrapper-level whitespace;
   - accepts exactly one complete response form;
   - preserves meaningful whitespace inside the rewritten body according to
     the `TextEnvelope` contract;
   - rejects missing, duplicated, nested, or trailing wrapper content;
   - returns the original body for `<unchanged/>`;
   - rejects an empty rewrite;
   - detects common refusal text before replacement.
5. Use the parser in Apple Intelligence, Ollama, and any OpenAI rewrite/cleanup
   path that receives this response contract.
6. Do not apply rewrite framing to autocomplete completions.
7. Decide explicitly whether dictation cleanup uses the same framed protocol;
   if it does, parse it before inserting text or falling back to the raw
   transcript.

Suggested API:

```swift
static func userPrompt(
    directive: String,
    text: String,
    boundary: String = UUID().uuidString
) -> String

static func parseModelResponse(
    _ response: String,
    original: String
) throws -> String
```

## Acceptance criteria

- Prompt construction compiles and every marker uses the same boundary.
- Source text containing fake response tags cannot escape its data boundary.
- Only the two documented response forms are accepted.
- Wrapper tags never appear in final user text.
- An unchanged response returns the original body.
- Empty, partial, or commentary-bearing responses fail closed.
- All rewrite providers use the same parser.
- Autocomplete still returns raw continuation text.

## Tests

Cover:

- deterministic boundary injection for tests;
- source text containing boundary-like and XML-like strings;
- valid multiline rewrite;
- unchanged response;
- empty rewrite;
- missing/extra/nested tags;
- content before or after the wrapper;
- refusal-like output;
- refusal-like original text;
- Unicode and newline preservation.

## Dependencies

- This is foundational for:
  - `08-harden-apple-intelligence-output-and-errors.md`
  - `07-harden-ollama-loopback-and-local-models.md`
  - `05-preserve-rewrite-boundary-whitespace.md`

## Do not copy as-is

The rebased prompt references an undefined `boundary`, and the provider paths
do not consistently parse the response format they request. Some existing
tests are uncompilable or stale:
`testSourceTextIsDelimited` passes a nonexistent `boundary:` argument, while
the dictation cleanup test still expects old `<source>...</source>` markers.
Reconcile prompt, parser, providers, and tests in one change.
