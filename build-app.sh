#!/bin/bash
# Builds Hubbub.app (menubar-only app) in the project folder
set -e
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)

APP=Hubbub.app
BUILD_DIR="${SCRATCH:-.build}"
if [ "${UNIVERSAL:-}" = "1" ]; then
  # arm64 + x86_64 fat binary; SwiftPM puts it under <scratch>/apple/Products/Release
  swift build -c release --scratch-path "$BUILD_DIR" --arch arm64 --arch x86_64
  # Location differs between toolchains (apple/Products/Release or out/Products/Release)
  BIN=$(ls "$BUILD_DIR"/apple/Products/Release/Hubbub "$BUILD_DIR"/out/Products/Release/Hubbub 2>/dev/null | head -1)
  [ -n "$BIN" ] || { echo "universal binary not found under $BUILD_DIR" >&2; exit 1; }
else
  swift build -c release --scratch-path "$BUILD_DIR"
fi
BIN="${BIN:-$BUILD_DIR/release/Hubbub}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns Resources/NotificationIcon.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Hubbub</string>
<key>CFBundleIdentifier</key><string>dev.hubbub.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>${APP%.app}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Hubbub contributors. MIT License.</string>
<key>NSAppleEventsUsageDescription</key><string>Hubbub types your reply into the terminal of the agent session that asked a question, only when you press a reply button and have enabled it in Settings.</string>
<key>HubbubRepo</key><string>karakayautku4/hubbub</string>
<key>LSUIElement</key><true/>
<key>NSFocusStatusUsageDescription</key><string>Hubbub can hold notifications while a Focus is on and send one summary afterwards.</string>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>dev.hubbub.app</string>
<key>CFBundleURLSchemes</key><array><string>hubbub</string></array>
</dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PL
# SCRATCH=<dir> overrides the build folder; UNIVERSAL=1 builds arm64+x86_64 (used by make-dmg.sh).
# SIGN_IDENTITY (or legacy SIGN_ID) = "Developer ID Application: Name (TEAMID)" signs with hardened runtime + timestamp;
# otherwise the app is ad-hoc signed.
SIGN_IDENTITY="${SIGN_IDENTITY:-${SIGN_ID:-}}"
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --options runtime --timestamp --entitlements packaging/entitlements.plist -s "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "Built $APP ($VERSION)"
