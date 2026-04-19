#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/ChatType.app"
PLIST="$APP/Contents/Info.plist"

"$ROOT/scripts/package_app.sh" >/dev/null

if /usr/bin/plutil -extract LSUIElement raw -o - "$PLIST" >/dev/null 2>&1; then
  echo "Packaged app must not declare LSUIElement in Info.plist; runtime should switch to accessory mode explicitly." >&2
  exit 1
fi

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if [[ "$ENTITLEMENTS" != *"com.apple.security.device.audio-input"* ]]; then
  echo "Packaged app is missing hardened runtime audio input entitlement." >&2
  exit 1
fi

echo "Packaged app metadata looks correct."
