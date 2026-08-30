#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source version.env

APP_NAME="NODAYSIDLE Voice"
APP="$ROOT/$APP_NAME.app"
DIST="$ROOT/dist"
DMG_NAME="NODAYSIDLE-Voice-$MARKETING_VERSION.dmg"
DMG="$DIST/$DMG_NAME"
PACKAGE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nodaysidle-voice-dmg.XXXXXX")"
STAGING="$PACKAGE_TMP/staging"
MOUNT_POINT="$PACKAGE_TMP/mount"
MOUNTED=0

cleanup() {
    if [[ "$MOUNTED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$PACKAGE_TMP"
}
trap cleanup EXIT

"$ROOT/Scripts/package_app.sh"
codesign --verify --deep --strict "$APP"

mkdir -p "$DIST" "$STAGING" "$MOUNT_POINT"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$DMG"
hdiutil verify "$DMG"

hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME.app"
diff -qr "$APP" "$MOUNT_POINT/$APP_NAME.app"
[[ "$(plutil -extract CFBundleIdentifier raw "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist")" == "com.nodaysidle.voice" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist")" == "$MARKETING_VERSION" ]]
file "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/NODAYSIDLEVoice" | grep -q 'arm64'
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED=0

(
    cd "$DIST"
    shasum -a 256 "$DMG_NAME" > SHA256SUMS.txt
)

echo "Created $DMG"
echo "Created $DIST/SHA256SUMS.txt"
