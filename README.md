# voice-dex

`voice-dex` is a native macOS dictation app built for a fast `F5 -> speak -> AI cleanup -> paste or clipboard` workflow.

It is designed as a lightweight operator tool:

- global `F5` hotkey
- floating HUD during recording and processing
- AI cleanup enabled by default
- paste directly into the focused editor when possible
- fall back to clipboard when there is no editable target
- local Codex bridge support plus a stable OpenAI-compatible transcription path

## Project Status

`voice-dex` `v0.1.0` is the first public launch build. It is optimized for Apple Silicon Macs and ships as an ad-hoc signed, non-notarized `.app` plus a release zip.

## Features

- Native menu bar app built with Swift and AppKit/SwiftUI
- Toggle recording on `F5`
- Floating HUD inspired by modern macOS dictation utilities
- Configurable transcription provider:
  - `openAICompatible` (recommended)
  - `codexChatGPTBridge` (experimental)
- Second-pass cleanup through an OpenAI-compatible chat endpoint
- Smart insertion:
  - paste when an editable field is focused
  - otherwise keep the result in the clipboard
  - when Accessibility permission is missing, explain the clipboard fallback
- Settings window for runtime configuration
- LaunchAgent install script for background startup

## Repository Layout

```text
Sources/VoiceDex/        App source
Tests/VoiceDexTests/     Swift tests
script/build_and_run.sh  Local build and launch entrypoint
scripts/check.sh         Build + test harness
scripts/package_app.sh   Build the packaged app and release zip
scripts/install_launch_agent.sh  Install background startup
docs/                    Architecture and release docs
version.env              Single version source for packaging
```

## Requirements

- macOS 13+
- Apple Silicon recommended
- `OPENAI_API_KEY` exported in the environment that launches the app
- Accessibility permission for automatic paste
- Microphone permission for recording

## Quick Start

1. Export your API key:

```bash
export OPENAI_API_KEY=your_key_here
```

2. Build and package the app:

```bash
./scripts/package_app.sh
```

3. Launch the packaged app:

```bash
open -n dist/VoiceDex.app
```

4. Grant permissions when prompted:
   - Microphone for recording
   - Accessibility for automatic paste

5. Put the cursor in TextEdit or another editable field, press `F5`, speak, then press `F5` again.

## Installation Notes

The public launch build is ad-hoc signed and **not notarized**. On first install, macOS may block the app.

- In Finder, right-click `VoiceDex.app`, then choose `Open`
- Or remove quarantine manually:

```bash
xattr -dr com.apple.quarantine /path/to/VoiceDex.app
```

The packaging script also creates a release asset zip at:

```text
dist/VoiceDex-0.1.0-macos-arm64.zip
```

## Build

```bash
swift build --package-path .
```

## Test

```bash
swift test --package-path .
./scripts/check.sh
```

## Run

```bash
./script/build_and_run.sh
```

This builds `dist/VoiceDex.app`, creates the release zip, signs the app locally with an ad-hoc signature, and launches it.

## Install Background Startup

```bash
./scripts/install_launch_agent.sh
```

## Config

The app stores config at:

```text
~/Library/Application Support/VoiceDex/config.json
```

If an older `HotkeyVoice` config exists, `voice-dex` migrates it on first launch.

## Publishing Notes

See:

- [Architecture](docs/architecture.md)
- [Release Process](docs/release.md)
- [GitHub Release Notes](docs/releases/v0.1.0.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).
