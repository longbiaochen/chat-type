# ChatType Repo Rules

- Preserve the single-trigger workflow: `F5` starts recording and `F5` stops recording.
- Treat `script/build_and_run.sh` and `scripts/check.sh` as the canonical local harness.
- Validate user-facing behavior through the real packaged app path in `dist/ChatType.app`, not only `swift build`.
- Keep paste behavior conservative: paste only when a focused editable target is detected; otherwise leave the final text in the clipboard.
- For this repo, "ship it" means more than source changes: run the canonical harness, build the packaged app, validate behavior from `dist/ChatType.app`, and keep release-facing docs current.
- Launch copy for this repo should describe the real public path first: local Codex desktop login, `F5` to record, transcription, and paste-versus-clipboard fallback.
- Keep the private ChatGPT backend dependency explicit in docs and UX. Do not describe it as a stable public API.
- Keep `OpenAI-Compatible` positioned as advanced recovery, not the default public story.
