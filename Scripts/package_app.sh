#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source version.env

APP_NAME="NODAYSIDLE Voice"
BINARY_NAME="NODAYSIDLEVoice"
APP="$ROOT/$APP_NAME.app"
PACKAGE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nodaysidle-voice-package.XXXXXX")"
STAGED_APP="$PACKAGE_TMP/$APP_NAME.app"
ICONSET="$PACKAGE_TMP/AppIcon.iconset"
trap 'rm -rf "$PACKAGE_TMP"' EXIT

swift build -c release
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$ICONSET"
cp ".build/release/$BINARY_NAME" "$STAGED_APP/Contents/MacOS/$BINARY_NAME"
cp "Assets/MenuBarN.png" "$STAGED_APP/Contents/Resources/MenuBarN.png"

cp "Assets/AppIcon.png" "$PACKAGE_TMP/AppIcon-1024.png"
sips -z 16 16 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
cp "$ICONSET/icon_16x16@2x.png" "$ICONSET/icon_32x32.png"
sips -z 64 64 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
cp "$ICONSET/icon_128x128@2x.png" "$ICONSET/icon_256x256.png"
sips -z 512 512 "$PACKAGE_TMP/AppIcon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
cp "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_512x512.png"
cp "$PACKAGE_TMP/AppIcon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"

cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>com.nodaysidle.voice</string>
<key>CFBundleExecutable</key><string>$BINARY_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>NODAYSIDLE Voice needs microphone access for dictation.</string>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>com.nodaysidle.voice.toggle</string>
  <key>CFBundleURLSchemes</key><array><string>nodaysidlevoice</string></array>
</dict></array>
</dict></plist>
PLIST

codesign --force --options runtime --entitlements "Resources/NODAYSIDLEVoice.entitlements" --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
rm -rf "$APP"
mv "$STAGED_APP" "$APP"
echo "Created $APP"
