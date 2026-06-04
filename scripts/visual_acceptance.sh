#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChatType"
APP_DIR="/Applications/ChatType.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/visual-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  echo "Run: $ROOT/scripts/visual_acceptance.sh --install" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.2

swift "$ROOT/scripts/prepare_visual_acceptance_screen.swift"
screencapture -x "$OUT_DIR/00-before.png"

OPEN_PID=""

cleanup() {
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" >/dev/null 2>&1; then
    kill "$OPEN_PID" >/dev/null 2>&1 || true
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

capture_state() {
  local state="$1"
  local output_file="$2"
  local log_file="$OUT_DIR/chattype-overlay-demo-$state.log"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  swift "$ROOT/scripts/prepare_visual_acceptance_screen.swift"
  CHATTYPE_OVERLAY_DEMO=1 open -W -n -g \
    --stdout "$log_file" \
    --stderr "$log_file" \
    "$APP_DIR" \
    --args --overlay-demo-state "$state" &
  OPEN_PID=$!

  sleep 0.8
  screencapture -x "$OUT_DIR/$output_file"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait "$OPEN_PID" >/dev/null 2>&1 || true
  OPEN_PID=""
}

capture_state "recording" "01-recording.png"
capture_state "processing" "02-processing.png"
capture_state "result" "03-result.png"
capture_state "error" "04-error.png"
capture_state "retryable-error" "05-retryable-error.png"

trap - EXIT

swift "$ROOT/scripts/verify_visual_acceptance.swift" \
  "$OUT_DIR/00-before.png" \
  "$OUT_DIR/01-recording.png" \
  "$OUT_DIR/02-processing.png" \
  "$OUT_DIR/03-result.png" \
  "$OUT_DIR/04-error.png" \
  "$OUT_DIR/05-retryable-error.png" | tee "$OUT_DIR/verification.txt"

cat >"$OUT_DIR/summary.md" <<SUMMARY
# ChatType Visual Acceptance

- Run ID: \`$RUN_ID\`
- App: \`$APP_BINARY\`
- Demo flag: \`CHATTYPE_OVERLAY_DEMO=1\`
- Evidence:
  - \`00-before.png\`
  - \`01-recording.png\`
  - \`02-processing.png\`
  - \`03-result.png\`
  - \`04-error.png\`
  - \`05-retryable-error.png\`
  - \`verification.txt\`
  - \`chattype-overlay-demo-*.log\`

SUMMARY

echo "Visual acceptance artifacts: $OUT_DIR"
