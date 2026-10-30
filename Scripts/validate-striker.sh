#!/usr/bin/env bash
# Striker + tab-engine health check over USB.
#
# Validates two things against a device running the tweak:
#   1. Striker answers on the loopback port (DevKit console is up and reachable).
#   2. The tab engine's view: dumps the live LINMainNavViewController and tails the
#      tweak log for the "[navbar] applied (modern UITab|viewControllers)" line, so
#      you can see which path TabEngine took on this iOS build.
#
# Requires: libimobiledevice (iproxy, idevice_id), python3, the striker submodule,
# and LinkedIn FOREGROUNDED on the device (Striker only serves while foreground,
# and DevKit must be enabled - it is by default). Reorder a tab in the LinkedIn
# Professional settings first so there is an "applied" line to read.
#
#   Scripts/validate-striker.sh
#   STRIKER_PORT=45801 Scripts/validate-striker.sh
set -uo pipefail

PORT="${STRIKER_PORT:-45801}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="$ROOT/Submodules/striker/driver/striker.py"
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*"; exit "${2:-1}"; }

command -v iproxy >/dev/null 2>&1 || fail "iproxy not found (brew install libimobiledevice)"
[ -f "$DRIVER" ] || fail "striker driver missing - run: git submodule update --init"
UDID="$(idevice_id -l 2>/dev/null | head -1)"
[ -n "$UDID" ] || fail "no device connected over USB"
say "device $UDID, port $PORT"

# Fresh forwarder: kill any stale one holding the port (a dead tunnel RSTs probes).
lsof -tiTCP:"$PORT" 2>/dev/null | xargs -r kill 2>/dev/null
iproxy "$PORT" "$PORT" >/dev/null 2>&1 &
IPROXY=$!
trap 'kill "$IPROXY" 2>/dev/null' EXIT
sleep 1

probe() { STRIKER_PORT="$PORT" python3 "$DRIVER" "$1" 2>&1; }

say "ping Striker (uivc)"
OUT="$(probe uivc)"
if printf '%s' "$OUT" | grep -qiE "ConnectionResetError|refused|timed out"; then
    fail "Striker not answering. Open LinkedIn and bring it to the foreground (DevKit must be on), then re-run." 2
fi
printf '%s\n' "$OUT" | head -30

say "live nav controller (expect LINMainNavViewController / a UITabBar)"
probe "uitree 50 6000" | grep -iE "MainNav|TabBar|UITab" | head -20

say "tab-engine decision + recent log (look for: [navbar] applied (modern UITab|viewControllers))"
probe "logtail 80" | grep -iE "\[navbar\]|\[devkit\]|\[boot\]" | tail -25

say "PASS - Striker answered; see the lines above for the tab-engine path"
