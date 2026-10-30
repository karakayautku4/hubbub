#!/bin/bash
# Builds a universal (arm64 + x86_64), ad-hoc signed Hubbub.app and packages it as:
#   dist/Hubbub-<version>.dmg   versioned (what the in-app updater looks for)
#   dist/Hubbub.dmg             stable name for the .../releases/latest/download/Hubbub.dmg link
#   dist/SHA256SUMS.txt
# Pure hdiutil + osascript (Finder lays out the window).
# Env: SCRATCH=<dir>   SwiftPM build folder (default .build-dmg; keeps your normal .build untouched)
#      ARCH_MODE=universal|native   (default universal; falls back to native if the toolchain can't)
#      SKIP_BUILD=1    reuse an existing ./Hubbub.app
#      NO_LAYOUT=1     skip the Finder/AppleScript window layout (headless machines)
#      SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   optional; hardened-runtime signing (default: ad-hoc)
#      NOTARY_PROFILE=<name>   optional `xcrun notarytool store-credentials` keychain profile; notarizes + staples
#                              (needs SIGN_IDENTITY). Setup: docs/RELEASING.md
# NOTE: build-app.sh rewrites ./Hubbub.app. Run this from a clean clone/copy if you keep a live app there.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)
VOL="Hubbub"
APP=Hubbub.app
DIST=dist
STAGE="$DIST/dmg-stage"
RW="$DIST/rw-$$.dmg"
MNT=""
cleanup() {
  [ -n "$MNT" ] && hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
  rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

if [ -d "/Volumes/$VOL" ]; then
  echo "A volume named '$VOL' is already mounted; eject it first." >&2; exit 1
fi

mkdir -p "$DIST"
export SCRATCH="${SCRATCH:-.build-dmg}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [ -n "$SIGN_IDENTITY" ] && ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  echo "SIGN_IDENTITY not found in the keychain; falling back to ad-hoc signing." >&2
  SIGN_IDENTITY=""
fi
if [ -n "$NOTARY_PROFILE" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "NOTARY_PROFILE is set but there is no usable SIGN_IDENTITY; skipping notarization." >&2; NOTARY_PROFILE=""
  elif ! xcrun --find notarytool >/dev/null 2>&1 || ! xcrun --find stapler >/dev/null 2>&1; then
    echo "notarytool/stapler not available (install Xcode); skipping notarization." >&2; NOTARY_PROFILE=""
  fi
fi
export SIGN_IDENTITY
if [ "${SKIP_BUILD:-}" != "1" ]; then
  if [ "${ARCH_MODE:-universal}" = "universal" ]; then
    if ! UNIVERSAL=1 ./build-app.sh; then
      echo "Universal build failed; falling back to the native architecture." >&2
      ./build-app.sh
    fi
  else
    ./build-app.sh
  fi
fi
[ -d "$APP" ] || { echo "$APP missing" >&2; exit 1; }

echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Hubbub")"
if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing with Developer ID (hardened runtime, timestamp)"
  codesign --force --deep --options runtime --timestamp --entitlements packaging/entitlements.plist --sign "$SIGN_IDENTITY" "$APP"
else
  # Ad-hoc signature (no Developer ID). No hardened runtime and no entitlements are needed.
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
if [ -n "$NOTARY_PROFILE" ]; then
  echo "Notarizing the app (this can take a few minutes)..."
  ditto -c -k --keepParent "$APP" "$DIST/notarize-app.zip"
  xcrun notarytool submit "$DIST/notarize-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$DIST/notarize-app.zip"
  xcrun stapler staple "$APP"
fi
if spctl --assess --type execute "$APP" 2>/dev/null; then
  echo "Gatekeeper: accepted"
else
  echo "Gatekeeper: rejected, as expected for an unsigned/ad-hoc app (users right-click -> Open once)."
fi

# --- stage contents ---
rm -rf "$STAGE" && mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "packaging/dmg/Read Me First.html" "$STAGE/"
swift scripts/make-dmg-background.swift "$STAGE/.background/background.png"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# --- writable image, Finder layout ---
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 30 ))
DMG="$DIST/Hubbub-$VERSION.dmg"
rm -f "$DMG" "$DIST/Hubbub.dmg" "$DIST/SHA256SUMS.txt"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null
MNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
[ -d "$MNT" ] || { echo "mount failed" >&2; exit 1; }

if [ "${NO_LAYOUT:-}" != "1" ]; then
  # Window content is 660x400; +22 for the title bar. Icon centres match the arrow in the background.
  if ! osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 542}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "$APP" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    set position of item "Read Me First.html" of container window to {590, 70}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
  then
    echo "WARNING: Finder layout failed (allow Terminal to control Finder in Privacy & Security > Automation). The DMG still works but is unstyled." >&2
  fi
  sync; sleep 2
fi
# Finder drops .VolumeIcon.icns during layout, so (re)install it afterwards
cp Resources/AppIcon.icns "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT" 2>/dev/null || true
SetFile -a V "$MNT/.background" "$MNT/.VolumeIcon.icns" 2>/dev/null || true
chmod -Rf go-w "$MNT" 2>/dev/null || true
hdiutil detach "$MNT" >/dev/null || { sleep 3; hdiutil detach "$MNT" -force >/dev/null; }
MNT=""
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing the DMG..."
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
  else
    echo "Signed but not notarized (set NOTARY_PROFILE to notarize)."
  fi
fi

cp "$DMG" "$DIST/Hubbub.dmg"
( cd "$DIST" && shasum -a 256 "Hubbub-$VERSION.dmg" "Hubbub.dmg" > SHA256SUMS.txt )

# --- verify the produced image ---
CHK=$(hdiutil attach "$DMG" -readonly -nobrowse -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
MNT="$CHK"
fail=0
[ -d "$CHK/$APP" ] || { echo "FAIL: app missing"; fail=1; }
[ "$(readlink "$CHK/Applications")" = "/Applications" ] || { echo "FAIL: Applications symlink"; fail=1; }
[ -f "$CHK/.background/background.png" ] || { echo "FAIL: background"; fail=1; }
[ -f "$CHK/.VolumeIcon.icns" ] || { echo "FAIL: volume icon"; fail=1; }
[ -f "$CHK/Read Me First.html" ] || { echo "FAIL: readme"; fail=1; }
codesign --verify --deep --strict "$CHK/$APP" || { echo "FAIL: signature in DMG"; fail=1; }
"$CHK/$APP/Contents/MacOS/Hubbub" --status >/dev/null 2>&1 || { echo "FAIL: --status"; fail=1; }
hdiutil detach "$CHK" >/dev/null 2>&1 || { sleep 3; hdiutil detach "$CHK" -force >/dev/null 2>&1 || true; }; MNT=""
[ $fail = 0 ] || exit 1

echo "Created:"
ls -lh "$DMG" "$DIST/Hubbub.dmg" "$DIST/SHA256SUMS.txt"
cat "$DIST/SHA256SUMS.txt"
