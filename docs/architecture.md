# Architecture

## Overview

`voice-dex` is a native macOS menu bar app with a narrow operator workflow:

1. User presses `F5`
2. App starts recording and shows a floating HUD
3. User presses `F5` again
4. Audio is transcribed
5. AI cleanup runs on the transcript by default
6. Final text is pasted or copied

## Runtime Components

- `AppCoordinator`
  - owns the product workflow
  - bridges hotkey, recording, transcription, cleanup, HUD, notifications, and insertion
- `HotkeyMonitor`
  - registers the global hotkey
- `AudioRecorder`
  - records mono WAV audio for short dictation sessions
- `ChatGPTTranscriber`
  - runs the transcription request using the configured provider
- `CodexAuthClient`
  - fetches local Codex auth state when the experimental bridge path is used
- `TextPostProcessor`
  - applies AI cleanup
- `RuntimePreflight`
  - validates the environment and required settings before recording starts
- `TextInjector`
  - copies text and pastes only when the focused target is editable
  - explains whether clipboard fallback happened because of a missing editable target or missing Accessibility permission
- `OverlayController`
  - renders the HUD shown during recording and processing
- `PreferencesWindowController`
  - renders the settings surface

## Provider Strategy

Two transcription paths exist:

- `codexChatGPTBridge`
  - useful for experimentation only
  - depends on the local Codex login state
  - not the default public-launch path
- `openAICompatible`
  - default public-launch path
  - preferred for production use
  - uses `/v1/audio/transcriptions`
  - supports stable OpenAI-compatible providers

Cleanup is enabled by default in `v0.1.0` and targets an OpenAI-compatible chat completions endpoint for light polishing after transcription.

## Packaging

- `version.env` is the single version source for release packaging metadata
- `scripts/package_app.sh` creates `dist/VoiceDex.app`
- `scripts/package_app.sh` also creates `dist/VoiceDex-<version>-macos-<arch>.zip`
- the app bundle is ad-hoc signed locally for development and public launch trials
- `script/build_and_run.sh` packages then launches
- `scripts/install_launch_agent.sh` installs the LaunchAgent
