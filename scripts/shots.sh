#!/usr/bin/env bash
# Captures the palette and Settings pages in dark and light into build/shots/, for visual review.
#
#   scripts/shots.sh             build once, then capture everything
#   scripts/shots.sh --no-build  reuse the last build (build/agent)
#
# Runs entirely in agent mode (APROPOS_AGENT=1): a separate Debug build in build/agent, started as its own process with
# no status item, hotkey, welcome window or activation, and fully transparent windows. It never touches the app
# you run with scripts/dev.sh, never brings another app to the front and never opens anything on your screen. It
# stops only the process it started. Fixture commands and context mean Accessibility access is not needed. Each image
# is drawn from the window's own views, so the glass shows no backdrop. Files are named panel-<state>-<mode>.png and
# settings-<page>-<mode>.png.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/agent/Build/Products/Debug/Apropos.app"
BIN="$APP/Contents/MacOS/Apropos"
OUT="$PWD/build/shots"
LOCK="build/shots.lock"
AGENT_PID=""

if [ "${1:-}" != "--no-build" ]; then
  (cd App && xcodegen generate >/dev/null)
  mkdir -p build
  if ! xcodebuild build -project App/Apropos.xcodeproj -scheme Apropos -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath build/agent -quiet 2>build/agent-errors.log; then
    echo "build failed:"
    grep -E "error:" build/agent-errors.log | head -10
    exit 1
  fi
fi

# One capture run at a time, so two sessions never fight over build/shots.
mkdir -p build "$OUT"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "another scripts/shots.sh run is active ($LOCK exists); wait for it or remove the lock if it crashed"
  exit 1
fi
stop_agent() {
  if [ -n "$AGENT_PID" ]; then
    kill "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
    AGENT_PID=""
  fi
}
cleanup() { stop_agent; rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT

# The remote control is a distributed notification; a tiny compiled helper posts it (osascript's bridge does not).
POST="$PWD/build/apropos-post"
if [ ! -x "$POST" ]; then
  cat > build/apropos-post.swift <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.zawalid.apropos.debug." + args[1]), object: args.count > 2 ? args[2] : nil, userInfo: nil,
    deliverImmediately: true)
SWIFT
  swiftc -O build/apropos-post.swift -o "$POST"
fi

# post <notification suffix> [object]
post() { "$POST" "$@"; }

# launch <mode> [KEY=VALUE ...]: starts one agent process with a fresh data directory, so shots never depend on the
# real settings and usage files.
launch() {
  local mode="$1"
  shift
  stop_agent
  local data
  data="$(mktemp -d "${TMPDIR:-/tmp}/apropos-shots.XXXXXX")"
  env APROPOS_AGENT=1 APROPOS_APPEARANCE="$mode" APROPOS_SNAPSHOT_DIR="$OUT" APROPOS_DATA_DIR="$data" "$@" "$BIN" >/dev/null 2>&1 &
  AGENT_PID=$!
  sleep 2
}

STATES=(
  "list|"
  "empty-search|APROPOS_PREVIEW_QUERY="
  "no-results|APROPOS_PREVIEW_QUERY=zzqx"
  "loading|APROPOS_PREVIEW_STATE=loading"
  "permission|APROPOS_PREVIEW_STATE=permission"
  "error|APROPOS_PREVIEW_STATE=failed"
  "popover|APROPOS_PREVIEW_ACTIONS=1"
  "usually-next|APROPOS_FIXTURE_PREDICTION=1"
  "send-rows|APROPOS_FIXTURE_COMMANDS=safari APROPOS_PREVIEW_SEND=rows"
  "send-list|APROPOS_FIXTURE_COMMANDS=safari APROPOS_PREVIEW_SEND=list"
  "send-confirm|APROPOS_FIXTURE_COMMANDS=safari APROPOS_PREVIEW_SEND=confirm"
  "send-error|APROPOS_FIXTURE_COMMANDS=safari APROPOS_PREVIEW_SEND=error APROPOS_FIXTURE_SEND_FAIL=1"
  "send-files|APROPOS_FIXTURE_COMMANDS=finder APROPOS_PREVIEW_SEND=list"
)

for mode in dark light; do
  for entry in "${STATES[@]}"; do
    label="${entry%%|*}"
    extra="${entry#*|}"
    # shellcheck disable=SC2086
    launch "$mode" APROPOS_FIXTURE_COMMANDS=finder APROPOS_FIXTURE_USAGE=1 \
      APROPOS_SNAPSHOT_NAME="panel-$label-$mode" $extra
    post toggle
    sleep 2
    echo "panel-$label-$mode"
  done

  launch "$mode" APROPOS_FIXTURE_COMMANDS=finder
  for page in general appearance context privacyAndData updates about; do
    post settings "$page"
    sleep 1.6
    mv "$OUT/settings-$page.png" "$OUT/settings-$page-$mode.png"
    echo "settings-$page-$mode"
  done
done
echo "done: $OUT"
