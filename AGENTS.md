# ChatType Runbook

## Repo Scope

- Owner/escalation: Longbiao for product behavior, installed app state, and release copy.
- This repo owns the native macOS dictation app `ChatType`, packaged output under `dist/`, and the installed app path `/Applications/ChatType.app`.
- The live app path is authoritative for permission and interaction verification; `dist/ChatType.app` is packaging output only.

## Canonical Commands

- Local harness: `script/build_and_run.sh`
- Test/check harness: `scripts/check.sh`
- Package app: `scripts/package_app.sh`
- Install packaged app: `scripts/install_app.sh`
- Visual acceptance: `./scripts/visual_acceptance.sh --install`
- Installed app smoke: `scripts/check_packaged_app.sh`

## Routine Operations

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Implement app behavior fix | `scripts/check.sh` | Unit/integration checks pass | Fix the first failing test; keep paste/permission regressions covered |
| Ship usable local build | `scripts/package_app.sh` then `scripts/install_app.sh` | Fresh `dist/ChatType.app` is installed to `/Applications/ChatType.app` | Rebuild and reinstall; never launch directly from `dist` for live verification |
| Run visual acceptance | `./scripts/visual_acceptance.sh --install` | Installed app launches through LaunchServices in overlay demo mode and captures recording/processing/result/error/retryable-error evidence | Inspect generated artifact directory, fix the HUD/state mismatch, and rerun |
| Verify first-run permissions | Reset TCC for installed app path, then launch `/Applications/ChatType.app` | System permission prompt fires from `not determined` state | Do not let setup preflights request permissions before the first-run path is observed |

## Troubleshooting

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Output pastes into the wrong place | Inspect focused editable target and run the installed app path | Text pastes only when a focused editable target exists; otherwise it stays in clipboard | Keep paste behavior conservative and debug AX/direct insertion path before changing STT cleanup |
| HUD or hotkey interaction changed | Use official Computer Use on the installed app | `F5` starts/stops, `ESC` cancels, inline close cancels, retry/re-entry works | Fix source, rebuild, reinstall, and rerun the full interaction branch |
| Permission flow regresses | Clean TCC state and installed app launch | Accessibility/Microphone prompts appear in the expected order | Add or update automated ordering tests, then repeat installed-app proof |

## Verification

- Verification ladder: unit tests, integration tests, then real installed-app user-flow testing. The first two are prechecks only.
- For native GUI work, use official Computer Use whenever clicks, hotkeys, focus, timing, modal state, permissions, or multi-step interaction are touched.
- ChatType Computer Use acceptance should cover: focus a real editable target, start with `F5`, stop with `F5`, cancel with `ESC`, cancel with inline close, retry after cancel/error, and observe paste-versus-clipboard result.
- For closeouts, report the installed-app user flow exercised, the live verification path, and the exact outcome observed.

## Release/Deploy

- "Ship it" means run the canonical harness, build, install to `/Applications/ChatType.app`, validate installed behavior, and keep release-facing docs current.
- After any fix reaches test/acceptance green, reinstall the freshly built app before reporting completion.
- Launch copy should describe the real public path: local Codex desktop login, `F5` to record, transcription, and paste-versus-clipboard fallback.

## Guardrails

- Preserve the single-trigger workflow: `F5` starts recording and `F5` stops recording.
- Do not run `ChatType.app` directly from `dist`.
- Keep `.notDetermined` permission paths as their own regression surface.
- Keep the private ChatGPT backend dependency explicit in docs and UX; do not describe it as a stable public API.
- Keep `OpenAI-Compatible` positioned as advanced recovery, not the default public story.

## Known State

- `dist/ChatType.app` is build output only.
- `/Applications/ChatType.app` is the app path for launch, permission, LaunchAgent, and user-flow proof.

## Browser Automation Constraint
- Follow the global `~/.codex/AGENTS.md` official browser/GUI policy: Browser plugin for unauthenticated local/public rendering, Chrome plugin for signed-in/default-profile browser state, and Computer Use only for native desktop boundaries.
- Keep only repo-specific verification surfaces here; do not copy the full global policy block into this runbook.
