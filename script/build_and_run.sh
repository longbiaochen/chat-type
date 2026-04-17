#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoiceDex"
APP_DIR="$ROOT/dist/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
LAUNCH_AGENT_LABEL="com.longbiao.voicedex"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

"$ROOT/scripts/package_app.sh" >/dev/null

LAUNCH_AGENT_BINARY=""
if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
  LAUNCH_AGENT_BINARY="$(plutil -extract ProgramArguments.0 raw -o - "$LAUNCH_AGENT_PLIST" 2>/dev/null || true)"
fi

if launchctl list | grep -q "$LAUNCH_AGENT_LABEL" && [[ "$LAUNCH_AGENT_BINARY" == "$APP_BINARY" ]]; then
  launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 &
else
  open -n "$APP_DIR"
fi
