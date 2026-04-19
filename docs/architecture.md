# ChatType Architecture

## Overview

`ChatType` is a native macOS menu bar app with a narrow workflow:

1. User presses `F5`
2. App starts recording and shows a compact HUD
3. User presses `F5` again
4. App validates local desktop login-state availability
5. Audio is sent to the ChatGPT backend transcription path
6. Result text is pasted or copied

The V1 architecture deliberately optimizes for zero-config usage on a Mac that already runs a signed-in Codex desktop session.

## Runtime Components

- `AppCoordinator`
  - owns hotkey, recording, transcription, setup-state refresh, and insertion
- `HotkeyMonitor`
  - registers the global `F5` shortcut
- `AudioRecorder`
  - records mono WAV clips for short dictation
- `CodexAuthClient`
  - reads local Codex desktop login state and returns the current ChatGPT bearer token
- `ChatGPTTranscriber`
  - calls the private ChatGPT backend transcription route with `Authorization: Bearer <token>`
  - measures `auth_ms` and `transcribe_ms`
  - applies a fixed prompt where supported
- `RuntimePreflight`
  - checks desktop host availability, login state, token availability, and any advanced recovery misconfiguration
- `TranscriptionPromptBuilder`
  - builds the fixed “directly usable text” prompt and optional hidden hint terms
- `TerminologyNormalizer`
  - applies deterministic post-STT terminology alignment without a second model call
- `TypeWhisperTerminologyImporter`
  - reads a manual snapshot from `~/Library/Application Support/TypeWhisper/dictionary.store`
  - converts enabled TypeWhisper term rows into ChatType-owned canonical terminology entries
- `LatencyRecorder`
  - appends per-dictation JSONL metrics under `~/Library/Application Support/ChatType/latency.jsonl`
- `TextInjector`
  - pastes only when an editable target exists; otherwise leaves text in the clipboard
- `DictationPipeline`
  - orchestrates transcription and deterministic normalization through testable seams
- `OverlayController`
  - renders the floating HUD
- `PreferencesWindowController`
  - shows onboarding, setup checks, and advanced recovery settings

## Provider Strategy

Two transcription routes exist:

- `codexChatGPTBridge`
  - default V1 route
  - recommended for launch
  - uses local signed-in Codex desktop login state
  - does not require an API key in the normal flow
- `openAICompatible`
  - advanced recovery route
  - not part of default onboarding
  - requires user-provided endpoint, model, and API key env var

## Output Strategy

`ChatType` now treats “directly usable STT text” as a single-stage outcome instead of `transcribe -> rewrite`.

Behavior:

- OpenAI-compatible recovery sends a fixed prompt through the official transcriptions API
- the desktop-login bridge tries the same prompt and retries without it if the private route rejects the field
- optional manual imports from TypeWhisper become ChatType-owned canonical terminology entries
- imported terminology is aligned by a deterministic local normalizer after transcription
- hidden `transcription.hintTerms` remain exact-only preservation hints
- no second model call is used in the default product path

## Benchmarking

- `scripts/benchmark_stt.sh` runs the packaged app in headless benchmark mode
- benchmark mode prints per-file `cold` and `warm` summaries with `auth_ms`, `transcribe_ms`, and `total_ms` p50/p95 values
- benchmark input audio files are supplied explicitly through the script arguments

## Packaging

- `version.env` is the single source of truth for version metadata
- `scripts/package_app.sh` builds `dist/ChatType.app`
- `scripts/install_app.sh` installs the packaged app to `/Applications/ChatType.app`
- `scripts/package_app.sh` also creates `dist/ChatType-<version>-macos-<arch>.zip`
- `scripts/package_app.sh` also creates `dist/ChatType-<version>-macos-<arch>.dmg`
- `scripts/install_launch_agent.sh` installs `me.longbiaochen.chattype`
- Homebrew Cask metadata is stored under `packaging/homebrew/Casks/chattype.rb`
