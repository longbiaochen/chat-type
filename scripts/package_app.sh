#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoiceDex"
BUILD_DIR="$ROOT/.build/debug"
APP_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
PLIST="$APP_DIR/Contents/Info.plist"
VERSION_ENV="$ROOT/version.env"

if [[ ! -f "$VERSION_ENV" ]]; then
  echo "Missing version source at $VERSION_ENV" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_ENV"

: "${VOICEDEX_VERSION:?VOICEDEX_VERSION is required}"
: "${VOICEDEX_BUILD:?VOICEDEX_BUILD is required}"

ARCH="$(uname -m)"
ZIP_PATH="$ROOT/dist/${APP_NAME}-${VOICEDEX_VERSION}-macos-${ARCH}.zip"

mkdir -p "$ROOT/dist"
rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS"

swift build --package-path "$ROOT"
cp "$BUILD_DIR/$APP_NAME" "$EXECUTABLE"
chmod +x "$EXECUTABLE"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VoiceDex</string>
  <key>CFBundleIdentifier</key>
  <string>com.longbiao.voicedex</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>voice-dex</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VOICEDEX_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VOICEDEX_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>voice-dex records short dictation clips so they can be transcribed.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Packaged $APP_DIR"
echo "Created $ZIP_PATH"
