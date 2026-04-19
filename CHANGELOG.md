# Changelog

## 0.1.2

- Added manual TypeWhisper terminology import in Settings and persisted the imported glossary into `~/Library/Application Support/ChatType/config.json`
- Added stronger deterministic post-STT terminology alignment without reintroducing a second AI cleanup pass
- Exposed exact and fuzzy terminology-alignment metrics in the dictation pipeline and test suite
- Updated public docs, release notes, landing page, and packaging metadata for the `v0.1.2` release surface

## 0.1.0

- Renamed the launch product from `voice-dex` to `ChatType`
- Made the local Codex desktop login-state route the default transcription path
- Simplified the main product to a single-stage STT flow instead of a second cleanup pass
- Added fixed transcription prompting plus hidden `transcription.hintTerms` for term preservation
- Added desktop-auth warm caching and per-dictation latency logging
- Added a packaged benchmark path via `scripts/benchmark_stt.sh`
- Added runtime setup states for missing host app, missing ChatGPT login, and missing desktop token
- Reworked Settings into a setup-first onboarding surface with microphone and Accessibility checks
- Moved `OpenAI-Compatible` transcription into an advanced recovery position
- Renamed packaged assets to `dist/ChatType.app`, `dist/ChatType-0.1.0-macos-arm64.zip`, and `dist/ChatType-0.1.0-macos-arm64.dmg`
- Added Homebrew Cask packaging metadata support under `packaging/homebrew/Casks/`
