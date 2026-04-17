# Release Process

## Local Release Checklist

1. Run `./scripts/check.sh`
2. Run `./scripts/package_app.sh`
3. Confirm the release asset exists: `dist/VoiceDex-0.1.0-macos-arm64.zip`
4. Launch `dist/VoiceDex.app`
5. Verify the public-launch defaults:
   - provider defaults to OpenAI-Compatible
   - cleanup is enabled
   - cleanup defaults target `https://api.openai.com/v1/chat/completions`
   - cleanup model defaults to `gpt-4.1-mini`
6. Verify packaging and startup:
   - menu bar item appears
   - settings window opens
   - app can be relaunched from the packaged bundle
7. Verify runtime behavior:
   - HUD appears on `F5`
   - recording stops on second `F5`
   - missing `OPENAI_API_KEY` produces a clear setup error before recording
   - paste vs clipboard fallback behaves correctly
   - missing Accessibility permission keeps the result in the clipboard with an explicit explanation
8. Re-test from the zipped release artifact:
   - unzip `dist/VoiceDex-0.1.0-macos-arm64.zip`
   - launch the extracted `VoiceDex.app`
   - follow the same install instructions used in the release notes
9. Confirm docs are aligned:
   - `README.md`
   - `docs/architecture.md`
   - `docs/releases/v0.1.0.md`
10. Publish the GitHub Release using `docs/releases/v0.1.0.md`

## Gatekeeper Notes

`v0.1.0` is ad-hoc signed and not notarized.

If macOS blocks the app:

- Right-click the app in Finder and choose `Open`
- Or remove quarantine:

```bash
xattr -dr com.apple.quarantine /path/to/VoiceDex.app
```

Document this clearly in the GitHub Release body.

## GitHub Publishing

Recommended repository defaults:

- repository name: `voice-dex`
- default branch: `main`
- visibility: public

## Follow-Up Work After v0.1.0

- add a production app icon
- add proper Developer ID signing
- notarize the `.app` or `.dmg`
- publish screenshots and a short demo video
- improve first-run onboarding for environment variables and permissions
