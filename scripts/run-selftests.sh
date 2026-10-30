#!/bin/bash
# Runs every headless `--selftest-*` flag of the Hubbub binary. Used by CI and locally.
# Usage: scripts/run-selftests.sh [--with-gui]
#   HUBBUB_BIN=path   binary to test (default .build/release/Hubbub, built if missing)
#   SELFTEST_TIMEOUT  seconds per test (default 120)
# --with-gui also runs the tests that need a window server / Metal device (`--selftest`, `--selftest-perf`).
# macOS has no `timeout`, so a perl alarm kills hung tests.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="${HUBBUB_BIN:-.build/release/Hubbub}"
LIMIT="${SELFTEST_TIMEOUT:-120}"
[ -x "$BIN" ] || swift build -c release || exit 1

TESTS=(providers quota a11y update budget export notifications fun halloween fx integration ui jobs themes prodfeatures progress reply settings perf-data)
GUI_TESTS=("" perf)
FLAGS=()
for t in "${TESTS[@]}"; do FLAGS+=("--selftest-$t"); done
if [ "${1:-}" = "--with-gui" ]; then
  for t in "${GUI_TESTS[@]}"; do FLAGS+=("--selftest${t:+-$t}"); done
fi

failed=()
for flag in "${FLAGS[@]}"; do
  printf '>>> %s\n' "$flag"
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$LIMIT" "$BIN" "$flag" > .selftest-out.log 2>&1
  rc=$?
  tail -n 3 .selftest-out.log
  if [ $rc -ne 0 ]; then
    [ $rc -eq 142 ] && echo "TIMEOUT after ${LIMIT}s"
    failed+=("$flag (exit $rc)")
  fi
done
rm -f .selftest-out.log

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "All ${#FLAGS[@]} self-tests passed"
else
  echo "FAILED: ${failed[*]}"
  exit 1
fi
