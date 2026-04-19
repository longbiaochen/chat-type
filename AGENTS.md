# ChatType Repo Rules

- Preserve the single-trigger workflow: `F5` starts recording and `F5` stops recording.
- Treat `script/build_and_run.sh` and `scripts/check.sh` as the canonical local harness.
- Build into `dist`, then install `dist/ChatType.app` to `/Applications/ChatType.app` before running or verifying behavior.
- Do not run `ChatType.app` directly from `dist`; that path is build output only and must not own live TCC permissions.
- For first-run macOS permission flows, verify from a clean TCC state on the installed `/Applications/ChatType.app` path. Do not let host/login/setup preflights run ahead of the system permission request when the permission state is still `not determined`.
- Treat `.notDetermined` permission paths as their own regression surface: keep an automated test for the ordering and do one real installed-app check after permission resets before calling the flow fixed.
- Keep paste behavior conservative: paste only when a focused editable target is detected; otherwise leave the final text in the clipboard.
- For this repo, "ship it" means more than source changes: run the canonical harness, build the packaged app, install it to `/Applications/ChatType.app`, validate behavior from that installed app, and keep release-facing docs current.
- Launch copy for this repo should describe the real public path first: local Codex desktop login, `F5` to record, transcription, and paste-versus-clipboard fallback.
- Keep the private ChatGPT backend dependency explicit in docs and UX. Do not describe it as a stable public API.
- Keep `OpenAI-Compatible` positioned as advanced recovery, not the default public story.
