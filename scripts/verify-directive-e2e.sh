#!/bin/bash
# verify-directive-e2e.sh — Task: confirm stacked directive cards visibly change
# model output on a real Mac (Linux CI cannot run this; wiring is unit/static-
# verified only there).
#
# Follows the verification recipes in CLAUDE.md: launch build, TextEdit typing
# for the ghost-text pill, dictation shortcut (hold ⇪Space / hyper+Space) for
# cleanup. Run each phase, eyeball the screenshots in /tmp/pluma-e2e/.
#
# Prereqs: Pluma built & installed (~/Applications/Pluma.app), Accessibility
# granted to Pluma and to your terminal (for System Events keystrokes).

set -euo pipefail
APP="$HOME/Applications/Pluma.app"
BUNDLE=com.scottlatz.Pluma
OUT=/tmp/pluma-e2e
mkdir -p "$OUT"

# Chains are stored as JSON-encoded Data under UserDefaults. Write them as hex.
write_chain() { # $1=key $2=json
  local hex
  hex=$(printf '%s' "$2" | xxd -p | tr -d '\n')
  defaults write "$BUNDLE" "$1" -data "$hex"
}

relaunch() {
  osascript -e 'tell application "Pluma" to quit' 2>/dev/null || true
  sleep 1
  open "$APP"
  sleep 3
}

type_in_textedit() { # $1=text
  osascript <<EOF
tell application "TextEdit"
  activate
  make new document
end tell
delay 1
tell application "System Events"
  keystroke "$1"
end tell
EOF
}

snap() { sleep "$2"; screencapture -x "$OUT/$1.png"; echo "saved $OUT/$1.png"; }

echo "=== Phase A: BASELINE completion (default chain: Match My Tone) ==="
defaults delete "$BUNDLE" pluma.completionChain 2>/dev/null || true
relaunch
type_in_textedit "The quarterly report covers three things we should discuss before the deadline and I think the most important one is"
snap baseline-completion 3

echo "=== Phase B: STACKED completion (Keep It Short + Full Sentences + Avoid Clichés) ==="
write_chain pluma.completionChain '["shortCompletions","fullSentences","avoidCliches"]'
relaunch
type_in_textedit "The quarterly report covers three things we should discuss before the deadline and I think the most important one is"
snap stacked-completion 3
echo ">>> Compare: stacked suggestion should be visibly SHORTER than baseline."

echo "=== Phase C: STACKED dictation cleanup (Bullet Points + Remove Filler) ==="
write_chain pluma.dictationCleanupChain '["removeFiller","bulletPoints"]'
relaunch
cat <<'MSG'
MANUAL STEP (audio cannot be synthesized reliably):
  1. Focus a TextEdit document.
  2. Hold the dictation chord (⇪Space / ⌃⌥⌘Space) and say:
     "um so first we need to uh finish the report, second um send it to
      finance, and third like schedule the review"
  3. Release. Cleaned text should insert as BULLET POINTS with fillers removed.
Press Enter here after dictating to capture the screenshot...
MSG
read -r
snap stacked-dictation 1
echo "=== Phase D: BASELINE dictation cleanup (defaults) — repeat the same utterance ==="
defaults delete "$BUNDLE" pluma.dictationCleanupChain 2>/dev/null || true
relaunch
echo "Dictate the same utterance again, then press Enter..."
read -r
snap baseline-dictation 1

echo
echo "PASS criteria:"
echo "  - stacked-completion.png suggestion is materially shorter / full-sentence vs baseline-completion.png"
echo "  - stacked-dictation.png output is bulleted, no 'um/uh/like'; baseline-dictation.png is prose"
echo "Screenshots in $OUT. Restore your own chains from the app UI when done."
