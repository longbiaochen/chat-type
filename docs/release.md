# ChatType Release Process

## Local Release Checklist

1. Run `./scripts/check.sh`
2. Run `./scripts/package_app.sh`
3. Confirm the release assets exist:
   - `dist/ChatType-0.1.0-macos-arm64.zip`
   - `dist/ChatType-0.1.0-macos-arm64.dmg`
4. Launch `dist/ChatType.app`
5. Verify setup states:
   - signed-in Codex desktop session shows as ready
   - microphone state is reported correctly
   - Accessibility state is reported correctly
6. Verify runtime behavior:
   - HUD appears on `F5`
   - recording stops on second `F5`
   - missing Codex desktop install produces a clear setup blocker
   - missing ChatGPT login in Codex produces a clear setup blocker
   - paste vs clipboard fallback behaves correctly
   - settings do not expose a second AI cleanup stage in the main flow
   - output remains directly usable without a second model call
7. Verify advanced recovery mode:
   - switching to `OpenAI-Compatible Recovery` exposes endpoint, model, and API env settings
   - missing API key in recovery mode produces a clear setup blocker
   - if `transcription.hintTerms` exists in config.json, filenames and product names are preserved
8. Re-test from the packaged release artifacts:
   - unzip `dist/ChatType-0.1.0-macos-arm64.zip`
   - launch the extracted `ChatType.app`
   - mount `dist/ChatType-0.1.0-macos-arm64.dmg`
   - launch the mounted `ChatType.app`
9. Update docs if any onboarding, naming, packaging, or launch assumptions changed.

## Gatekeeper Notes

`v0.1.0` is ad-hoc signed and not notarized.

If macOS blocks the app:

- right-click `ChatType.app` and choose `Open`
- or remove quarantine:

```bash
xattr -dr com.apple.quarantine /path/to/ChatType.app
```

## Homebrew Cask

Keep the cask file aligned with the release artifact:

```text
packaging/homebrew/Casks/chattype.rb
```

If the asset filename or release URL format changes, update the cask in the same change.

## Follow-Up Work After v0.1.0

- notarize the `.app` or `.dmg`
- publish a dedicated Homebrew tap
- broaden first-run diagnostics for desktop-host failures
- keep benchmark samples around for 3s / 10s / 30s regression checks
