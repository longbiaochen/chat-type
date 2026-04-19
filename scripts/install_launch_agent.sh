#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChatType"
APP_BINARY="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/me.longbiaochen.chattype.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/com.longbiao.chattype.plist"
VOICEDEX_PLIST="$HOME/Library/LaunchAgents/com.longbiao.voicedex.plist"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.longbiao.hotkeyvoice.plist"

if [[ ! -x "$APP_BINARY" ]]; then
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>me.longbiaochen.chattype</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/chattype.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/chattype.log</string>
</dict>
</plist>
PLIST

launchctl unload "$LEGACY_PLIST" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
launchctl unload "$VOICEDEX_PLIST" >/dev/null 2>&1 || true
rm -f "$VOICEDEX_PLIST"
launchctl unload "$OLD_PLIST" >/dev/null 2>&1 || true
rm -f "$OLD_PLIST"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"
echo "Installed launch agent at $PLIST"
