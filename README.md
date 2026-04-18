# ChatType

`ChatType` is a native macOS dictation app for people who already use ChatGPT through a local Codex desktop session and want the fastest possible `F5 -> speak -> paste` workflow.

It is intentionally opinionated:

- global `F5` hotkey
- native menu bar app
- zero-config default route through your local Codex desktop login state
- single-stage STT output tuned for direct paste
- conservative paste behavior
- clipboard fallback when paste is not safe
- optional advanced recovery route for OpenAI-compatible APIs

The repository name is still `voice-dex`, but the launch product is `ChatType`.

## Product Promise

- No extra dictation subscription
- No API key in the normal path
- No local model download or tuning
- Install once, sign into Codex on this Mac, press `F5`, speak, and get text back

## Current Status

`ChatType` `v0.1.0` is the first packaged launch candidate. It ships as an ad-hoc signed, non-notarized `.app` plus GitHub release `.zip` and `.dmg` artifacts.

## How It Works

1. Install `ChatType`
2. Launch it on a Mac that already has Codex desktop installed and signed in with ChatGPT
3. Grant microphone permission
4. Grant Accessibility if you want auto-paste
5. Put the cursor in Notes, Mail, Slack, or another editable target
6. Press `F5`, speak, press `F5` again
7. `ChatType` sends the recording through the local login-state bridge to the ChatGPT backend transcription path
8. `ChatType` applies a deterministic terminology-preservation pass when you define hidden `hintTerms`
9. The result is pasted into the focused app or left in the clipboard when paste is not safe

## Installation

### Downloaded app

1. Build and package:

```bash
./scripts/package_app.sh
```

2. Launch:

```bash
open -n dist/ChatType.app
```

3. If macOS blocks the app on first launch:

```bash
xattr -dr com.apple.quarantine /path/to/ChatType.app
```

### Homebrew Cask metadata

Homebrew packaging metadata lives at:

```text
packaging/homebrew/Casks/chattype.rb
```

This repo does not yet publish a dedicated Homebrew tap, but the cask file is kept current with the release artifact format.

## Advanced Recovery Route

If the desktop-login path is unavailable, `ChatType` still includes an advanced recovery route for OpenAI-compatible transcription APIs.

That route is intentionally not part of the default onboarding. It requires:

- your own endpoint
- your own model choice
- your own API key environment variable

## Output Quality

`ChatType` no longer uses a second AI cleanup pass in the default product path.

Instead it improves output at transcription time:

- OpenAI-compatible recovery uses the official transcription `prompt` parameter
- the desktop-login bridge attempts the same prompt and automatically retries without it if the private route rejects that field
- optional hidden `transcription.hintTerms` preserve filenames, product names, and other critical terms without another model call

## Repository Layout

```text
Sources/VoiceDex/                 App source for the ChatType executable target
Tests/VoiceDexTests/              Swift tests
script/build_and_run.sh           Canonical local launch path
scripts/check.sh                  Build + test harness
scripts/package_app.sh            Builds dist/ChatType.app plus release zip and dmg
packaging/homebrew/Casks/         Homebrew Cask metadata
scripts/install_launch_agent.sh   Installs LaunchAgent for ChatType
docs/                             Product and release docs
version.env                       Version metadata source
```

## Build And Verify

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./script/build_and_run.sh
```

Benchmark the real packaged path with your own sample audio:

```bash
./scripts/benchmark_stt.sh ~/bench/3s.wav ~/bench/10s.wav ~/bench/30s.wav
```

## Config

`ChatType` stores runtime config at:

```text
~/Library/Application Support/ChatType/config.json
```

It migrates older config from:

- `~/Library/Application Support/VoiceDex/config.json`
- `~/Library/Application Support/HotkeyVoice/config.json`

## Risks And Boundaries

`ChatType` V1 deliberately depends on a private backend path plus a local signed-in Codex desktop session.

That means:

- it is fast and simple for existing ChatGPT desktop users
- it may break if upstream desktop-login or backend behavior changes
- it is not positioned as an enterprise-safe or long-term stable public API integration
- the desktop bridge prompt path is opportunistic and falls back to plain transcription if unsupported

## Docs

- [Architecture](docs/architecture.md)
- [Release Process](docs/release.md)
- [Release Notes](docs/releases/v0.1.0.md)
- [Product PRD](docs/chattype-v1-prd.md)

## License

MIT. See [LICENSE](LICENSE).
