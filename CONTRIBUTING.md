# Contributing

## Development Flow

1. Run `./scripts/check.sh` before pushing changes.
2. Use `./script/build_and_run.sh` to validate the packaged app path.
3. Keep `version.env` as the single source of truth for release version metadata.
4. Update docs when changing:
   - permissions
   - host-app requirements
   - transcription route defaults
   - packaging or startup behavior
   - release assets or installation steps

## Coding Standards

- Keep the app focused and macOS-native.
- Keep the zero-config desktop-login flow simple and explicit.
- Treat private-backend risk as a product constraint, not a hidden implementation detail.
- Keep paste behavior conservative: paste only into a focused editable target; otherwise preserve the final text in the clipboard.

## Verification

Minimum verification for product changes:

- `swift build --package-path .`
- `swift test --package-path .`
- packaged app launch through `./script/build_and_run.sh`
- release packaging through `./scripts/package_app.sh` when versioning, packaging, or install docs change

For UI changes, verify the actual window or HUD behavior in the running app.

## Public Launch Expectations

- Keep `codexChatGPTBridge` as the recommended V1 default unless there is a deliberate product decision to move away from the desktop-login route.
- Keep `openAICompatible` as an advanced recovery path, not part of first-run onboarding.
- If a change affects permissions, host requirements, or Gatekeeper behavior, update `README.md` and `docs/release.md` in the same change.
