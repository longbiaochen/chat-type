# ChatType V1 PRD

## Summary

`ChatType` is a native macOS voice input tool for office users who already pay for ChatGPT and already run a local Codex desktop session. The core promise is simple: install once, no API key, no local model setup, press `F5`, speak, get text back.

## Product Comparison Matrix

| Product | Main model posture | Setup burden | Ongoing user cost | Cross-app insertion | Zero-config for existing ChatGPT payer | Core weakness vs ChatType |
| --- | --- | --- | --- | --- | --- | --- |
| Wispr Flow | cloud-first | low | extra subscription | yes | no | user pays again |
| Aqua Voice | cloud/model-provider heavy | low-medium | extra subscription | yes | no | broader, heavier product surface |
| TypeWhisper | local-first + plugins | medium-high | low-medium | yes | no | plugin and model tuning burden |
| Superwhisper | hybrid local/cloud | medium | subscription or BYOK | yes | no | still a model/config product |
| TapWisper | BYO provider | medium | provider spend | yes | no | still needs provider setup |
| VoiceCommand | local STT + cloud command | medium | provider spend | yes | no | still needs keys and cloud selection |
| **ChatType** | **local login-state bridge to ChatGPT backend** | **very low** | **no extra app subscription** | **yes** | **yes** | **private backend dependency and host-app dependency** |

## Product Positioning

- Product name: `ChatType`
- Category: desktop voice input for office work
- Primary user: existing ChatGPT payer who wants faster writing without API keys or local model ops
- Primary jobs:
  - dictate emails, notes, chat replies, prompts, and briefs
  - avoid local model setup
  - avoid a second dictation subscription

## Core Value Proposition

- You already pay for ChatGPT.
- Install ChatType.
- Press `F5`.
- Speak.
- Get text back in the active app.

## V1 Scope

### Included

- native macOS menu bar app
- zero-config default route through local signed-in Codex desktop login state
- setup checks for host login, microphone, and Accessibility
- safe paste into editable targets
- clipboard fallback otherwise
- GitHub release zip plus Homebrew Cask metadata

### Phased

- hidden `transcription.hintTerms` for terminology preservation
- packaged benchmark workflow for cold / warm regression checks
- advanced recovery route for OpenAI-compatible APIs

### Excluded

- enterprise/private deployment positioning
- Windows or iOS
- local model management
- multi-provider onboarding

## Key Risks

- V1 depends on a private backend path and local desktop login-state behavior.
- Upstream changes can break transcription without any public API compatibility guarantee.
- The product must be honest about this dependency in UI and docs.

## Success Criteria

- fast first successful dictation after install
- most users complete setup without touching advanced settings
- strong repeat usage for short-form writing tasks
