# Main integration issue briefs

These files are self-contained source material for creating individual GitHub
issues. They describe changes that are valuable in
`cloudai/build-rewrite-app-bd38` but need to be integrated deliberately into
the current `main` architecture.

Do not merge or cherry-pick the feature branch wholesale. Its provider,
Service, view-model, project, validation, and documentation changes were
rebased across a newer recipe-chain, autocomplete, dictation, global-hotkey,
and non-sandboxed architecture. Several resulting implementations do not
compile or contradict the product that `main` ships.

Each implementation should start from the latest `main`; the source branch is
reference material, not the intended base branch.

## Recommended sequence

1. [Pin XcodeGen and regenerate the project](13-pin-xcodegen-and-regenerate-project.md)
2. [Package a privacy manifest](02-package-privacy-manifest.md)
3. [Frame and parse rewrite responses](09-frame-and-parse-rewrite-responses.md)
4. [Preserve rewrite boundary whitespace](05-preserve-rewrite-boundary-whitespace.md)
5. [Preserve pasteboard contents](04-preserve-pasteboard-contents.md)
6. [Enforce operation timeouts](06-enforce-operation-timeouts.md)
7. [Align Service metadata](14-align-service-info-plist-metadata.md)
8. [Harden Apple Intelligence handling](08-harden-apple-intelligence-output-and-errors.md)
9. [Harden Ollama loopback and local-model handling](07-harden-ollama-loopback-and-local-models.md)
10. [Prevent stale rewrite results](10-prevent-stale-rewrite-results.md)
11. [Improve VoiceOver labels](11-improve-voiceover-labels.md)
12. [Expand hardening test coverage](12-expand-hardening-test-coverage.md)
13. [Add CI build, test, and release verification](01-add-ci-build-test-release-verification.md)
14. [Update privacy and release documentation](03-update-privacy-and-release-documentation.md)
15. [Document the local test command](15-document-local-test-command.md)
16. [Ignore Python cache files](16-ignore-python-cache-files.md)

Dependencies in each brief are descriptive rather than GitHub issue numbers so
the files remain useful before the issues are created.
