# ChatType

[中文说明](README.zh-CN.md)

`ChatType` is a native macOS dictation app for people who already use ChatGPT through a local Codex desktop session and want the fastest possible `F5 -> speak -> paste` workflow.

Public landing page: [longbiaochen.github.io/chat-type](https://longbiaochen.github.io/chat-type/)

It is intentionally opinionated:

- global `F5` hotkey
- native menu bar app
- zero-config default route through your local Codex desktop login state
- single-stage STT output tuned for direct paste
- conservative paste behavior
- clipboard fallback when paste is not safe
- manual TypeWhisper terminology import for stronger post-STT term alignment
- optional advanced recovery route for OpenAI-compatible APIs

## Product Promise

- No extra dictation subscription
- No API key in the normal path
- No local model download or tuning
- Install once, sign into Codex on this Mac, press `F5`, speak, and get text back

## Current Status

`ChatType` `v0.1.2` is the current public release. `./scripts/package_app.sh` expects a stable local signing identity and emits a locally signed, non-notarized `.app` plus GitHub release `.zip` and `.dmg` artifacts.

## How It Works

1. Install `ChatType`
2. Install the packaged app to `/Applications/ChatType.app`, then launch that installed copy on a Mac that already has Codex desktop installed and signed in with ChatGPT
3. Grant microphone permission
4. Grant Accessibility if you want auto-paste
5. Put the cursor in Notes, Mail, Slack, Codex, or another editable target
6. Press `F5`, speak, press `F5` again
7. `ChatType` sends the recording through the local login-state bridge to the ChatGPT backend transcription path
8. Optional: import a TypeWhisper terminology snapshot in Settings to strengthen post-STT technical-term alignment
9. `ChatType` applies a deterministic local terminology-alignment pass plus any hidden exact `hintTerms`
10. The result is pasted into the focused app or left in the clipboard when paste is not safe
11. Chinese output defaults to Simplified Chinese unless the original speech clearly asks for Traditional Chinese

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

- Releases: [github.com/longbiaochen/chat-type/releases](https://github.com/longbiaochen/chat-type/releases)
- Current release page: [v0.1.2](https://github.com/longbiaochen/chat-type/releases/tag/v0.1.2)

## TypeWhisper Terminology Import

`ChatType` still avoids a second AI cleanup pass in the default product path.

Instead, `v0.1.2` adds a deterministic terminology-alignment layer:

- import a TypeWhisper terminology snapshot from Settings with `Import from TypeWhisper`
- keep the imported glossary as ChatType-owned local config
- align tool names, product names, and technical terms after STT without another model call
- keep hidden `transcription.hintTerms` as exact-only preservation hints for filenames and other critical literals

## Advanced Recovery Route

If the desktop-login path is unavailable, `ChatType` still includes an advanced recovery route for OpenAI-compatible transcription APIs.

That route is intentionally not part of the default onboarding. It requires:

- your own endpoint
- your own model choice
- your own API key environment variable

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

Advanced terminology options:

- import TypeWhisper terminology from the Settings window with `Import from TypeWhisper`
- keep `transcription.hintTerms` for exact-only custom terms you want preserved even without a TypeWhisper import

## Risks And Boundaries

`ChatType` V1 deliberately depends on a private backend path plus a local signed-in Codex desktop session.

That means:

- it is fast and simple for existing ChatGPT desktop users
- it may break if upstream desktop-login or backend behavior changes
- it is not positioned as an enterprise-safe or long-term stable public API integration
- the desktop bridge prompt path is opportunistic and falls back to plain transcription if unsupported

## Docs

- [中文说明](README.zh-CN.md)
- [Architecture](docs/architecture.md)
- [Release Process](docs/release.md)
- [Release Notes](docs/releases/v0.1.2.md)
- [Product PRD](docs/chattype-v1-prd.md)

## License

MIT. See [LICENSE](LICENSE).
