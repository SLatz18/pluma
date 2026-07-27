# Rewrite Privacy Policy

Effective July 27, 2026

Rewrite is designed to process writing locally on your Mac.

## Data handling

- **Apple Intelligence:** Text sent to Apple’s Foundation Models framework is
  processed by the on-device system model. Rewrite does not transmit that text
  to the app developer.
- **Ollama:** If you choose Ollama, Rewrite sends text only to the Ollama server
  at `127.0.0.1:11434` on your Mac. Rewrite requires metadata showing that a
  model is stored locally and blocks redirects away from loopback before
  sending text. Because Ollama is a separate user-controlled process, enable
  Ollama’s local-only mode if you need to prevent Ollama itself from using any
  cloud features.
- **Selected and playground text:** Rewrite processes text only after you invoke
  the Service or press the playground’s rewrite button. Service text is held in
  memory only for the operation. Playground text remains visible in app memory
  while Rewrite is running, but is not persisted and is discarded when the app
  quits.
- **Preferences:** The selected action, provider, and Ollama model name are
  stored in the app’s local, unencrypted `UserDefaults` until you change them,
  choose **Reset Rewrite Settings**, or remove the app’s data.

Rewrite has no account system, analytics, advertising, tracking, remote backend,
or telemetry. It does not sell or share personal data, and it holds no
server-side data that needs to be deleted. You can stop Ollama processing at any
time by selecting Apple Intelligence or stopping Ollama.

## Contact

For privacy questions, open an issue in the
[Rewrite repository](https://github.com/SLatz18/rewrite-mac/issues).

Material changes to this policy will be recorded in this repository.
