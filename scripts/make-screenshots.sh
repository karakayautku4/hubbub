#!/bin/bash
# Renders the README UI screenshots (Live, Insights, History, Awards, Details, Settings tabs, Expand window; light, Halloween).
#
# How: it runs a *sandboxed copy* of the real app (own bundle id dev.hubbub.shots, a throw-away HOME full of invented
# sessions from scripts/seed-demo-events.py) and grabs its windows with `screencapture -l`, so the 3D stage and
# translucency look exactly like the real thing. Nothing from your real sessions, settings or quota is used, and your
# own Hubbub instance is never touched.
#
# Needs: a GUI session, the release binary (swift build -c release), Pillow (pip3 install --user pillow),
# Screen Recording permission for your terminal, and (only for the Expand-window shots) Accessibility permission, because
# the window is opened with a ⌘E keystroke. Without Accessibility the Expand shots are skipped.
#   scripts/make-screenshots.sh                 all UI shots -> docs/images/ui/*.png
#   SHOTS=light scripts/make-screenshots.sh     only one run: light | halloween
# The animated scene GIFs and theme stills come from scripts/make-gifs.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BIN="${HUBBUB_BIN:-$ROOT/.build/release/Hubbub}"
[ -x "$BIN" ] || swift build -c release
OUT=docs/images/ui
WORK="$ROOT/.shots-work"
HOMEDIR="$WORK/home"
APP="$WORK/app/Hubbub.app"
DOMAIN=dev.hubbub.shots
PID=; SLEEPER=
mkdir -p "$OUT" "$WORK"
rm -rf "$HOMEDIR" "$WORK/app"

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
  if [ -n "$SLEEPER" ]; then kill "$SLEEPER" 2>/dev/null || true; fi
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Minimal bundle: a distinct bundle id keeps preferences away from the real app; no URL scheme is declared so
# Launch Services never starts routing hubbub:// links to this copy.
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Hubbub"
PL="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $DOMAIN" -c "Add :CFBundleExecutable string Hubbub" \
  -c "Add :CFBundlePackageType string APPL" -c "Add :CFBundleName string Hubbub" -c "Add :LSUIElement bool true" "$PL"
codesign --force -s - "$APP" >/dev/null 2>&1
swiftc -O scripts/winid.swift -o "$WORK/winid"
sleep 900 & SLEEPER=$!   # Copilot treats a session as live while the pid in its lock file exists

prefs() { # <theme> <dark 0|1>
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  defaults write "$DOMAIN" cachedQuota -dict entitlement -float 1000 percentRemaining -float 64 remaining -float 640 \
    used -float 360 plan pro resetDate 2099-01-01 unlimited -bool false
  defaults write "$DOMAIN" theme "$1"
  defaults write "$DOMAIN" hasOnboarded -bool YES
  defaults write "$DOMAIN" stageHintDismissed -bool YES
  defaults write "$DOMAIN" showWelcome -bool NO
  if [ "$2" = 1 ]; then defaults write "$DOMAIN" AppleInterfaceStyle Dark; fi
}

launch() { # <halloween 0|1>
  rm -rf "$HOMEDIR"; mkdir -p "$HOMEDIR"
  python3 scripts/seed-demo-events.py "$HOMEDIR" "$SLEEPER"
  open -n -a "$APP" --env CFFIXED_USER_HOME="$HOMEDIR" --env HOME="$HOMEDIR" --env HUBBUB_HALLOWEEN="$1"
  sleep 12
  PID=$(pgrep -f "$APP/Contents/MacOS/Hubbub" | head -1 || true)
  [ -n "$PID" ] || { echo "app did not start" >&2; exit 1; }
}
quit() { kill "$PID"; sleep 2; PID=; }

go() { open -a "$APP" "$1"; sleep "${2:-3}"; }
cap() { # <name> [width]: grabs the largest window of the sandboxed app
  local id; id=$("$WORK/winid" "$PID")
  [ "$id" != 0 ] || { echo "no window for $1" >&2; return 0; }
  screencapture -x -o -l "$id" "$WORK/$1.raw.png"
  python3 scripts/shots_post.py "$WORK/$1.raw.png" "$OUT/$1.png" "${2:-880}"
}
expand() { # <name>: ⌘E opens the Expand window; skipped when Accessibility is not granted
  if osascript -e 'tell application "System Events" to keystroke "e" using command down' >/dev/null 2>&1; then
    sleep 4; cap "$1" 1100
    osascript -e 'tell application "System Events" to keystroke "w" using command down' >/dev/null 2>&1 || true
  else
    echo "Accessibility not granted: skipping $1" >&2
  fi
}

screens() { # <suffix> <full 0|1>
  go hubbub://open 4; cap "live-$1"
  expand "expand-$1"
  go hubbub://open 3
  if [ "$2" = 1 ]; then
    go hubbub://insights; cap "insights-$1"
    go hubbub://history; cap "history-$1"
    go hubbub://achievements; cap "awards-$1"
    go hubbub://session/demo-live 4; cap "details-$1"
    for tab in general appearance providers alerts; do go "hubbub://settings/$tab" 2; cap "settings-$tab-$1"; done
    go hubbub://open 3
  fi
}

run() { # <name> <theme> <dark> <halloween> <full>
  prefs "$2" "$3"; launch "$4"; screens "$1" "$5"; quit
}

want() { [ "${SHOTS:-all}" = all ] || [ "${SHOTS:-all}" = "$1" ]; }
if want light; then run light space 0 0 1; fi
# dark: `run dark wizard 1 0 1` is disabled; AppleInterfaceStyle in the sandbox domain does not switch the popover to dark.
if want halloween; then run halloween farm 0 1 0; fi
ls -la "$OUT"
