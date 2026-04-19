# ChatType

`ChatType` is a native macOS dictation app for people who already use ChatGPT through a local Codex desktop session and want the fastest possible `F5 -> speak -> paste` workflow.

Public landing page: [longbiaochen.github.io/chattype](https://longbiaochen.github.io/chattype/)

It is intentionally opinionated:

- global `F5` hotkey
- native menu bar app
- zero-config default route through your local Codex desktop login state
- single-stage STT output tuned for direct paste
- conservative paste behavior
- clipboard fallback when paste is not safe
- optional advanced recovery route for OpenAI-compatible APIs

## Product Promise

- No extra dictation subscription
- No API key in the normal path
- No local model download or tuning
- Install once, sign into Codex on this Mac, press `F5`, speak, and get text back

## Current Status

`ChatType` `v0.1.1` is the current M1 release. `./scripts/package_app.sh` expects a stable local signing identity and emits a locally signed, non-notarized `.app` plus GitHub release `.zip` and `.dmg` artifacts.

## How It Works

1. Install `ChatType`
2. Install the packaged app to `/Applications/ChatType.app`, then launch that installed copy on a Mac that already has Codex desktop installed and signed in with ChatGPT
3. Grant microphone permission
4. Grant Accessibility if you want auto-paste
5. Put the cursor in Notes, Mail, Slack, or another editable target
6. Press `F5`, speak, press `F5` again
7. `ChatType` sends the recording through the local login-state bridge to the ChatGPT backend transcription path
8. `ChatType` applies a deterministic terminology-preservation pass when you define hidden `hintTerms`
9. The result is pasted into the focused app or left in the clipboard when paste is not safe
10. Chinese output defaults to Simplified Chinese unless the original speech clearly asks for Traditional Chinese

## Installation

### Downloaded app

1. Build and package:

```bash
./scripts/package_app.sh
```

2. Install the packaged app to `/Applications`:

```bash
./scripts/install_app.sh
```

If you intentionally need an ad-hoc build for throwaway debugging, opt into it explicitly:

```bash
CHATTYPE_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

That fallback is not recommended for normal use. On recent macOS versions it can open Accessibility settings without creating a toggleable `ChatType` row.

3. Launch the installed app:

```bash
open -n /Applications/ChatType.app
```

Do not launch `dist/ChatType.app` directly. The `dist` copy is packaging output only; live permissions and verification must bind to `/Applications/ChatType.app`.

4. If macOS blocks the app on first launch:

```bash
xattr -dr com.apple.quarantine /path/to/ChatType.app
```

### Homebrew Cask metadata

Homebrew packaging metadata lives at:

```text
packaging/homebrew/Casks/chattype.rb
```

This repo does not yet publish a dedicated Homebrew tap, but the cask file is kept current with the release artifact format.

### Release Download

- Releases: [github.com/longbiaochen/chattype/releases](https://github.com/longbiaochen/chattype/releases)
- Current release page: [v0.1.1](https://github.com/longbiaochen/chattype/releases/tag/v0.1.1)

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
- Chinese output is steered to Simplified Chinese by prompt and normalized back from Traditional when needed
- optional hidden `transcription.hintTerms` preserve filenames, product names, and other critical terms without another model call

## Repository Layout

```text
Sources/VoiceDex/                 App source for the ChatType executable target
Tests/VoiceDexTests/              Swift tests
script/build_and_run.sh           Canonical local build -> install -> run path
scripts/check.sh                  Build + test harness
scripts/package_app.sh            Builds dist/ChatType.app plus release zip and dmg
scripts/install_app.sh            Installs dist/ChatType.app to /Applications/ChatType.app
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

Post a release update to X through the official API CLI:

```bash
scripts/post_x.sh --print "ChatType update"
scripts/post_x.sh "ChatType update"
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
- [Release Notes](docs/releases/v0.1.1.md)
- [Product PRD](docs/chattype-v1-prd.md)

## License

MIT. See [LICENSE](LICENSE).
