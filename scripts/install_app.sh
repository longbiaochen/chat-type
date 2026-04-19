#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT/dist/ChatType.app"
TARGET_APP="/Applications/ChatType.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
fi

pkill -x ChatType >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed $TARGET_APP"
