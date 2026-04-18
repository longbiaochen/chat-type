#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ChatType"
BUILD_DIR="$ROOT/.build/debug"
APP_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PLIST="$APP_DIR/Contents/Info.plist"
VERSION_ENV="$ROOT/version.env"
ICONSET_DIR="$ROOT/dist/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"

if [[ ! -f "$VERSION_ENV" ]]; then
  echo "Missing version source at $VERSION_ENV" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$VERSION_ENV"

: "${CHATTYPE_VERSION:?CHATTYPE_VERSION is required}"
: "${CHATTYPE_BUILD:?CHATTYPE_BUILD is required}"

ARCH="$(uname -m)"
ZIP_PATH="$ROOT/dist/${APP_NAME}-${CHATTYPE_VERSION}-macos-${ARCH}.zip"
DMG_PATH="$ROOT/dist/${APP_NAME}-${CHATTYPE_VERSION}-macos-${ARCH}.dmg"
DMG_STAGING_DIR="$ROOT/dist/.dmg-staging"

mkdir -p "$ROOT/dist"
rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR"

swift build --package-path "$ROOT"
cp "$BUILD_DIR/$APP_NAME" "$EXECUTABLE"
chmod +x "$EXECUTABLE"
swift "$ROOT/scripts/render_app_icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ChatType</string>
  <key>CFBundleIdentifier</key>
  <string>me.longbiaochen.chattype</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>ChatType</string>
  <key>CFBundleName</key>
  <string>ChatType</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${CHATTYPE_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${CHATTYPE_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>ChatType records short dictation clips and sends them through your local ChatGPT desktop login path.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"

echo "Packaged $APP_DIR"
echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
