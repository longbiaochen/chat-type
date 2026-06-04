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
  - public README or launch copy

## Coding Standards

- Keep the app focused and macOS-native.
- Keep the zero-config ChatGPT account flow simple and explicit.
- Treat private-backend risk as a product constraint, not a hidden implementation detail.
- Keep paste behavior conservative: paste only into a focused editable target; otherwise preserve the final text in the clipboard.

## Verification

Minimum verification for product changes:

- `swift build --package-path .`
- `swift test --package-path .`
- packaged app launch through `./script/build_and_run.sh`
- release packaging through `./scripts/package_app.sh` when versioning, packaging, or install docs change

For UI changes, verify the actual window or HUD behavior in the running app. For HUD or visual-state changes, run `./scripts/visual_acceptance.sh --install` and keep the generated `dist/visual-acceptance/<run-id>` path in the closeout. The script is the visual smoke gate; interactive changes still need the installed-app Computer Use pass described in `AGENTS.md`.

## Public Launch Expectations

- Keep `chatGPTManagedAuth` as the recommended V1 default unless there is a deliberate product decision to move away from the ChatGPT account route.
- Keep `openAICompatible` as an advanced recovery path, not part of first-run onboarding.
- If a change affects permissions, host requirements, Gatekeeper behavior, versioned release surfaces, or launch copy, update `README.md`, `README.zh-CN.md`, and `docs/release.md` in the same change.
