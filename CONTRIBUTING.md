# Contributing

## Development Flow

1. Run `./scripts/check.sh` before pushing changes.
2. Use `./script/build_and_run.sh` to validate the packaged app path.
3. Keep `version.env` as the single source of truth for release version metadata.
4. Update docs when changing:
   - permissions
   - hotkeys
   - provider configuration
   - packaging or startup behavior
   - release assets or installation steps

## Coding Standards

- Keep files focused and macOS-native.
- Prefer AppKit for system integration and SwiftUI for bounded settings surfaces.
- Avoid hidden magic defaults. Expose operator-facing configuration clearly.
- Keep comments sparse and only where they reduce real ambiguity.

## Verification

Minimum verification for product changes:

- `swift build --package-path .`
- `swift test --package-path .`
- packaged app launch through `./script/build_and_run.sh`
- release packaging through `./scripts/package_app.sh` when versioning, packaging, or install docs change

For UI changes, verify the actual window or HUD behavior in the running app.

## Public Launch Expectations

- Keep `openAICompatible` as the recommended default production path unless a deliberate release decision changes it.
- Treat `codexChatGPTBridge` as experimental in public-facing copy.
- Keep paste behavior conservative: paste only into a focused editable target; otherwise preserve the final text in the clipboard.
- If a change affects permissions, environment variables, or Gatekeeper behavior, update `README.md` and `docs/release.md` in the same change.
