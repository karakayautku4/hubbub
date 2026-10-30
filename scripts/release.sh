#!/bin/bash
# One-command release: scripts/release.sh [--publish] [--draft] [--dry-run]
#   (default)   build the DMG, create tag v<VERSION> and a DRAFT GitHub release with the DMGs + SHA256SUMS.txt
#   --publish   publish immediately instead of leaving a draft
#   --dry-run   do everything except tag / push / gh release (builds the DMG, prints the commands, edits the cask)
# Optional signing/notarization via env: SIGN_IDENTITY, NOTARY_PROFILE (see docs/RELEASING.md). Unset = ad-hoc.
# Does not push anything except the tag it creates.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=0 DRY=0
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH=1 ;;
    --draft) PUBLISH=0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n 2,7p "$0"; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
run() { if [ $DRY = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

VERSION=$(tr -d '[:space:]' < VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] || die "VERSION '$VERSION' is not semver"
TAG="v$VERSION"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash first"
if [ $DRY = 0 ]; then
  command -v gh >/dev/null || die "gh CLI not found"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated (gh auth login)"
  gh release view "$TAG" >/dev/null 2>&1 && die "release $TAG already exists"
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git rev-list -n1 "$TAG")" = "$(git rev-parse HEAD)" ] || die "tag $TAG exists but does not point at HEAD"
fi

echo "==> Release $TAG ($([ $PUBLISH = 1 ] && echo publish || echo draft)$([ $DRY = 1 ] && echo ', dry-run'))"
echo "==> Self-tests"
swift build -c release
scripts/run-selftests.sh

echo "==> DMG"
./make-dmg.sh
DMG="dist/Hubbub-$VERSION.dmg"
[ -f "$DMG" ] && [ -f dist/Hubbub.dmg ] && [ -f dist/SHA256SUMS.txt ] || die "expected artifacts missing in dist/"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "sha256 $SHA"

CASK=packaging/homebrew/Casks/hubbub.rb
sed -i '' -E "s/^( *version )\"[^\"]*\"/\1\"$VERSION\"/; s/^( *sha256 )\"[^\"]*\"/\1\"$SHA\"/" "$CASK"
echo "==> Cask updated ($CASK; review and commit it yourself, it is not part of the release commit):"
printf '  version "%s"\n  sha256 "%s"\n' "$VERSION" "$SHA"

NOTES="Download **Hubbub.dmg**, open it and drag Hubbub to Applications. Signed with a Developer ID and notarized by Apple. Details: https://github.com/karakayautku4/hubbub#-install"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  run git tag -a "$TAG" -m "Hubbub $VERSION"
fi
run git push origin "refs/tags/$TAG"
ARGS=("$TAG" "$DMG" dist/Hubbub.dmg dist/SHA256SUMS.txt --title "Hubbub $VERSION" --generate-notes --notes "$NOTES")
[ $PUBLISH = 1 ] || ARGS+=(--draft)
run gh release create "${ARGS[@]}"
echo "==> Done. $([ $PUBLISH = 1 ] || echo 'Review the draft on GitHub, then click Publish.')"
