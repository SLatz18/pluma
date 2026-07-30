## Summary

<!-- What changed and why. Link related issues. -->

## Privacy

- [ ] Behavior still matches [PRIVACY.md](../PRIVACY.md) for the paths I touched
- [ ] No new persistence of transcripts, audio, field text, or screen OCR
- [ ] No analytics or remote pluma backend introduced

## Test plan

- [ ] `./scripts/bootstrap.sh` (if sources were added/removed)
- [ ] `xcodebuild … test` (or describe manual Mac verification)
- [ ] New UI reuses `Pluma/DesignSystem` or documents a platform-native exception
- [ ] Checked keyboard navigation and the minimum window size
- [ ] Checked light, dark, increased-contrast, and reduced-motion behavior
- [ ] Added preview/gallery coverage for new component states
