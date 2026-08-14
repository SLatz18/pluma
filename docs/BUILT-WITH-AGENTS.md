# How pluma was built: AI agents, engineered

pluma is a native macOS app — Swift 6 strict concurrency, AppKit overlays,
Carbon hotkeys, a HID event tap — written almost entirely by AI coding agents
directed by one person. This document explains the workflow, because the
interesting part is not *that* agents wrote the code; it is the engineering
system that made their output shippable.

The numbers, as of `0.1.x`: roughly 20,000 lines of app code, 433 test
functions across 37 test files, two dozen merged pull requests, 50 tracked
issues, and a git history where every merge references the issue it closes.

## The cast

Several different agent products contributed, each where it is strongest:

- **Claude Code on the Mac** — the primary developer. It can build, run the
  test suite, launch the app, drive other apps via System Events, and take
  screenshots to verify UI changes end-to-end. Most PRs originate here.
- **Cloud agents on Linux** (Cursor background agents, Codex, and for a time a
  Replit agent) — parallel work on well-specified features and docs. A native
  macOS app cannot even compile on their VMs, so [AGENTS.md](../AGENTS.md)
  tells them exactly which checks *are* runnable on Linux (design-system
  drift, plist validation, the shipping-contract validator) and which claims
  they must leave for a Mac to verify. You can still see their fingerprints in
  the history (`cloudai/*` branches, a `replit/*` PR).
- **The human** — product direction, taste, priorities, beta testing on real
  hardware, and the final merge decision. Nothing lands on `main` without a
  human-observed verification pass.

## The system that keeps agents honest

Agent output is only as good as the feedback loops around it. This repo's
loops, in the order they fire:

1. **An operating manual the agents actually read.** [CLAUDE.md](../CLAUDE.md)
   is the contract: build commands, architecture map, house rules, and — most
   valuable — a *Toolchain traps* section of hard-won failures (a
   `swift-frontend` compiler crash with its exact repro conditions, a runtime
   trap from closure isolation inheritance with the `otool` recipe that proves
   a callback is safe). Every trap in that file cost real debugging time once,
   and has not been paid for twice.
2. **Durable agent memory.** [.agents/memory/](../.agents/memory/) holds
   decision records with explicit *Why* lines — e.g. a code review that failed
   solely because new files were never registered in the generated Xcode
   project, now a written rule rather than a repeatable mistake.
3. **Self-imposed lints, because agents drift.**
   [`scripts/check-design-system.sh`](../scripts/check-design-system.sh)
   blocks raw colors and one-off UI outside the design system;
   [`scripts/validate-shipping.py`](../scripts/validate-shipping.py) enforces
   the privacy contract in code (no analytics SDKs, Ollama pinned to loopback,
   entitlements exactly as documented); CI fails if the committed Xcode
   project drifts from `project.yml`, or if the asset catalog would ship
   broken.
4. **Tests as the merge gate.** `main` is PR-protected with a required check;
   the full macOS suite runs in CI on every PR. Agents write tests alongside
   features because reviews reject anything that arrives without them.
5. **End-to-end verification, not vibes.** CLAUDE.md records the repo's
   verification recipes — launch the build, keystroke 40 characters into
   TextEdit via System Events, watch for the ghost-text pill; post synthetic
   `CGEvent`s to exercise a hotkey. "It compiles" is not "it works" for an app
   whose job is riding other apps' text fields.
6. **Decisions are written down when they are made.**
   [docs/SHIPPING_DECISIONS.md](SHIPPING_DECISIONS.md) is a dated record —
   including one major decision that was later reversed and is preserved as
   superseded rather than erased.
   [tools/CapsSpike/NOTES.md](../tools/CapsSpike/NOTES.md) is a standalone
   spike with a rejected-alternatives matrix for the Caps Lock expander. When
   a future session asks "why is it built this way?", the answer exists.
7. **Git discipline sized for agents.** Each working session gets its own
   worktree and feature branch; destructive git commands require explicit
   human confirmation; history is never rewritten. The conventions are spelled
   out in CLAUDE.md so every fresh agent session starts with the same rules.

## What this workflow is not

It is not "prompt, paste, ship." The commit history shows regressions caught
by beta testing, follow-up PRs that fix what an earlier PR broke, and issues
filed by one agent session against another's work. The value of the setup is
that those failures were caught by the system — tests, lints, CI, human
verification — rather than by users.

If you are building something similar, the three highest-leverage artifacts
here are probably [CLAUDE.md](../CLAUDE.md)'s toolchain traps (write down
every failure that cost more than an hour), the self-imposed lints (encode
your taste as a script the agent cannot skip), and the verification recipes
(give the agent a way to *see* the app working, not just compiling).
