#!/bin/bash
# Steady-state performance check for every theme (offscreen, needs a Metal device).
# Usage: scripts/perf-check.sh [agents] [seconds-per-theme]
# Thresholds (override via env): PERF_MAX_TICK_MS=8 PERF_MAX_RENDER_MS=60 PERF_MAX_CPU_PCT=30
#                                PERF_MAX_MEM_GROWTH_MB=60 PERF_MAX_MEM_MB=1500
set -euo pipefail
cd "$(dirname "$0")/.."
AGENTS="${1:-8}"
SECONDS_PER="${2:-3}"
BIN="${HUBBUB_BIN:-.build/release/Hubbub}"
if [ ! -x "$BIN" ]; then swift build -c release; fi
exec "$BIN" --selftest-perf --perf-agents "$AGENTS" --perf-seconds "$SECONDS_PER"
