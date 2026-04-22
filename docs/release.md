# ChatType Release Process

## Local Release Checklist

1. Run `./scripts/check.sh`
2. Run `./scripts/package_app.sh`
3. Confirm the release assets exist:
   - `dist/ChatType-0.1.2-macos-arm64.zip`
   - `dist/ChatType-0.1.2-macos-arm64.dmg`
4. Install `dist/ChatType.app` to `/Applications/ChatType.app`
5. Launch `/Applications/ChatType.app`
6. Verify setup states:
   - signed-in Codex desktop session shows as ready
   - microphone state is reported correctly
   - Accessibility state is reported correctly
   - denied microphone state exposes `Open Microphone Settings`
   - missing Accessibility exposes `Guide Accessibility Access`, `Open Accessibility Settings`, and `Refresh Status`
7. Verify runtime behavior:
   - HUD appears on `F5`
   - recording stops on second `F5`
   - missing Codex desktop install produces a clear setup blocker
   - missing ChatGPT login in Codex produces a clear setup blocker
   - first-run microphone flow still surfaces the native macOS system prompt
   - denied microphone flow jumps to `Privacy & Security > Microphone`
   - Accessibility guidance opens the correct page and shows the drag-to-authorize helper for the packaged app
   - paste only reports success when an editable focus target exists
   - clipboard fallback keeps the latest transcript available for manual `Cmd+V`
   - settings do not expose a second AI cleanup stage in the main flow
   - TypeWhisper terminology import is visible in Settings and succeeds against a valid local dictionary
   - output remains directly usable without a second model call
8. Verify advanced recovery mode:
   - switching to `OpenAI-Compatible Recovery` exposes endpoint, model, and API env settings
   - missing API key in recovery mode produces a clear setup blocker
   - if `transcription.hintTerms` exists in config.json, filenames and product names are preserved
   - simplified Chinese remains the default when the recognizer drifts into Traditional Chinese
9. Re-test from the packaged release artifacts:
   - unzip `dist/ChatType-0.1.2-macos-arm64.zip`
   - install the extracted `ChatType.app` to `/Applications/ChatType.app`
   - launch `/Applications/ChatType.app`
   - mount `dist/ChatType-0.1.2-macos-arm64.dmg`
   - install the mounted `ChatType.app` to `/Applications/ChatType.app`
   - launch `/Applications/ChatType.app`
10. If you are announcing the release on X, preview the outgoing post first and send it through `chrome-use` on the managed Chrome for Testing session:
   - `scripts/post_x.sh --print "ChatType update"`
   - `scripts/post_x.sh "ChatType update"`
   - treat the post as complete only after the command returns the published post URL
11. Update docs if any onboarding, naming, packaging, or launch assumptions changed.

## Gatekeeper Notes

`v0.1.2` is expected to be locally signed with Apple Development or Developer ID Application and is not notarized.

`./scripts/package_app.sh` now fails fast when no stable signing identity is available. Only use `CHATTYPE_ALLOW_ADHOC_SIGNING=1` for throwaway local debugging, because ad-hoc builds can break the Accessibility repair flow.

Do not verify or repair permissions from `dist/ChatType.app`. Install the packaged app to `/Applications/ChatType.app` first so TCC binds to the real runtime path.

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

## Follow-Up Work After v0.1.2

- notarize the `.app` or `.dmg`
- publish a dedicated Homebrew tap
- broaden first-run diagnostics for desktop-host failures
- keep benchmark samples around for 3s / 10s / 30s regression checks
