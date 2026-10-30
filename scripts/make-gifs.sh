#!/bin/bash
# Records the animated GIFs + stills used in the README by running the real 3D stage offscreen (--fxshot).
# Needs a GUI session with Metal, the release binary, and Pillow (pip3 install --user pillow). Synthetic demo data only.
#   scripts/make-gifs.sh                          everything (hero, 9 themes, 2 Halloween GIFs)
#   GIF_THEMES="space farm" scripts/make-gifs.sh  only some themes
#   GIF_FPS=10 GIF_SECS=4 GIF_WIDTH=560 GIF_COLORS=128 GIF_ZOOM=1.2 override the defaults
# Output: docs/images/hero.gif, docs/images/themes/<theme>.gif + <theme>.jpg, docs/images/halloween-<theme>.gif
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${HUBBUB_BIN:-.build/release/Hubbub}"
[ -x "$BIN" ] || swift build -c release
OUT=docs/images
WORK=.shots-work
FPS="${GIF_FPS:-10}"; SECS="${GIF_SECS:-4}"; WIDTH="${GIF_WIDTH:-560}"; COLORS="${GIF_COLORS:-128}"; ZOOM="${GIF_ZOOM:-1.2}"
mkdir -p "$OUT/themes" "$WORK"
trap 'rm -rf "$WORK"' EXIT

# record <theme> <name> <halloween 0|1> <width> <colors> [NAME=VALUE env overrides ...]
record() {
  local theme="$1" name="$2" hw="$3" width="$4" colors="$5"; shift 5
  rm -f "$WORK/$name"-*.png
  env HUBBUB_HALLOWEEN="$hw" FX_SIZE=640x360 FX_ZOOM="$ZOOM" FX_EVERY="$(python3 -c "print(1/$FPS)")" "$@" \
    "$BIN" --fxshot "$theme" "$WORK/$name.png" "$SECS" >/dev/null
  # drop the first frames (scene warm-up)
  local frames; frames=$(ls "$WORK/$name"-*.png | sort -V | tail -n +4)
  # shellcheck disable=SC2086
  python3 scripts/gif_assemble.py "$WORK/$name.gif" "$width" "$FPS" "$colors" $frames
}

for t in ${GIF_THEMES:-space kitchen prison football farm impostor wizard galactic fellowship}; do
  record "$t" "$t" 0 "$WIDTH" "$COLORS"
  mv "$WORK/$t.gif" "$OUT/themes/$t.gif"
  last=$(ls "$WORK/$t"-*.png | sort -V | tail -n 1)
  sips -s format jpeg -s formatOptions 72 --resampleWidth 800 "$last" --out "$OUT/themes/$t.jpg" >/dev/null
done

if [ -z "${GIF_THEMES:-}" ]; then
  record space hero 0 800 160 FX_SIZE=800x450
  mv "$WORK/hero.gif" "$OUT/hero.gif"
  for t in wizard farm; do
    record "$t" "hw-$t" 1 "$WIDTH" "$COLORS"
    mv "$WORK/hw-$t.gif" "$OUT/halloween-$t.gif"
  done
fi
ls -la "$OUT" "$OUT/themes"
