---
name: Conversation awareness conventions
description: Decisions behind the conversation-context / draft-reply feature to stay consistent with in future work.
---

- Conversation reading is gated on BOTH toggles: the existing screen-context switch AND the sibling "Conversation awareness" toggle (`Preferences.conversationAwarenessActive`). New context features should ride the same gate rather than adding another permission surface.
  **Why:** privacy posture — screen context is the user's single opt-in to "pluma may look at my screen"; siblings refine it but never widen it.
- Draft-reply rides the dictation *cleanup* provider choice (Apple/Ollama/OpenAI), not the rewrite provider. **Why:** drafting happens at the end of a dictation; the "after you speak" model is the one that speaks for the user, and it is the only provider enum that already includes OpenAI.
- Captured conversation text must stay transient: task-local values only, never persisted, never logged verbatim (log lengths/sources only — see PRIVACY.md diagnostics promise).
- Global hotkeys: Carbon silently refuses duplicate chords in one process; every shortcut recorder must conflict-check against all four slots (rewrite ⇪E, dictation ⇪Space, clipboard ⇪R, draft ⇪D). Hyperkey 3- and 4-modifier chords count as the same press.
- This repo cannot be built on Replit (macOS/Xcode only); after adding files run `xcodegen generate` on a Mac — project.yml globs the `Pluma/` and `PlumaTests/` dirs so no manual project edits are needed.
