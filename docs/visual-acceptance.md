# ChatType Visual Acceptance

Use this chain for ChatType HUD or interaction-facing visual work after unit/integration tests pass.

## Required Command

```sh
./scripts/visual_acceptance.sh --install
```

The command packages the current build, installs it to `/Applications/ChatType.app`, moves the cursor to the main screen, launches one installed-app demo process per HUD state through LaunchServices with `CHATTYPE_OVERLAY_DEMO=1` and `--overlay-demo-state`, captures each HUD state, and runs the screenshot verifier.

## Evidence

Each run writes a timestamped directory under:

```text
dist/visual-acceptance/<run-id>
```

The directory must contain:

- `00-before.png`
- `01-recording.png`
- `02-processing.png`
- `03-result.png`
- `04-error.png`
- `05-retryable-error.png`
- `verification.txt`
- `summary.md`

## Closeout Rule

For ChatType UI closeouts, report:

- the visual acceptance artifact directory
- whether `verification.txt` passed
- the installed-app live flow used for interaction acceptance
- the observed paste-versus-clipboard result when transcription/injection behavior was touched

The scripted visual run does not replace Computer Use interaction acceptance. It only proves the installed build can render the expected HUD states and retry affordance.
