# Privacy

pluma (full name: plumafina) is designed so most writing stays on your Mac.
There is no account system, no analytics SDK, and no pluma backend.

## Default path (on-device)

- **Apple Intelligence** rewrites, completions, and dictation cleanup use
  Apple’s on-device Foundation Models. pluma does not send that text to the
  app developer.
- **Ollama** (optional) sends text only to `http://127.0.0.1:11434` on this
  Mac. Ollama is a separate process you control; if you enable any Ollama cloud
  features yourself, that is outside pluma.
- **Apple Speech** dictation (default) transcribes on-device. Audio is not
  written to disk and is not transmitted by pluma.

## Optional OpenAI path

Dictation can use OpenAI for live transcription and/or cleanup when you choose
those providers and save an API key. In that mode:

- Microphone audio and/or transcript text are sent to OpenAI.
- The API key is stored in the macOS Keychain, not in preferences files.
- Apple Intelligence / Ollama remain available; OpenAI is never required.

The Dictation page states which path is active before you talk.

## What pluma reads

| Capability | What it reads | Stored? |
|---|---|---|
| Rewrite selection | Selected text, on demand | No |
| Autocomplete | Focused field text before the caret | In memory for the active suggestion only |
| Screen context (opt-in) | Frontmost window OCR at request time | No — discarded after the request |
| Style memory (opt-in) | Accepted suggestion phrases only | Local JSON, capped at 300 entries |
| Spelling memory (opt-in) | Accepted misspelling → correction pairs | Local JSON, capped at 200 entries |
| Style profile (opt-in) | Imported writing guide | Local markdown, capped at 3,000 characters |
| Dictation | Microphone while the shortcut is held | No audio on disk; transcript in memory for one insertion |

Password fields (`AXSecureTextField`) are never read for autocomplete.

## Diagnostics

A local diagnostics log under Application Support records operational events
(permission state, lengths, errors). It does not record field contents,
screen OCR text, or suggestion text.

## Contact

Open a GitHub issue or use
[private vulnerability reporting](https://github.com/SLatz18/rewrite-mac/security)
for security-sensitive privacy questions.
