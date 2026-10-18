#!/usr/bin/env bash
# Captures the palette and Settings pages in dark and light into build/shots/, for visual review.
#
#   scripts/shots.sh             build once, then capture everything
#   scripts/shots.sh --no-build  reuse the last build (build/dev)
#
# Uses the Debug build's remote control: environment variables seed fixture commands and context (so Accessibility
# access is not needed) and a distributed notification opens the panel or a Settings page. Each image is a snapshot of
# Cue's own window, so the glass shows no backdrop. Files are named panel-<state>-<mode>.png and
# settings-<page>-<mode>.png.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/dev/Build/Products/Debug/Cue.app"
OUT="$PWD/build/shots"
FRONT="${CUE_SHOTS_APP:-Finder}"

if [ "${1:-}" != "--no-build" ]; then
  scripts/dev.sh >/dev/null
fi
pkill -x Cue 2>/dev/null || true
mkdir -p "$OUT"

# The remote control is a distributed notification; a tiny compiled helper posts it (osascript's bridge does not).
POST="$PWD/build/cue-post"
if [ ! -x "$POST" ]; then
  cat > build/cue-post.swift <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.zawalid.cue.debug." + args[1]), object: args.count > 2 ? args[2] : nil, userInfo: nil,
    deliverImmediately: true)
SWIFT
  swiftc -O build/cue-post.swift -o "$POST"
fi

# post <notification suffix> [object]
post() { "$POST" "$@"; }

# launch <mode> [open --env arguments...]
launch() {
  local mode="$1"
  shift
  pkill -x Cue 2>/dev/null || true
  sleep 0.6
  # A fresh data directory per launch keeps the shots independent of the real settings and usage files.
  local data
  data="$(mktemp -d "${TMPDIR:-/tmp}/cue-shots.XXXXXX")"
  open --env CUE_APPEARANCE="$mode" --env CUE_SNAPSHOT_DIR="$OUT" --env CUE_DATA_DIR="$data" "$@" "$APP"
  sleep 2
}

STATES=(
  "list|"
  "empty-search|--env CUE_PREVIEW_QUERY="
  "no-results|--env CUE_PREVIEW_QUERY=zzqx"
  "loading|--env CUE_PREVIEW_STATE=loading"
  "permission|--env CUE_PREVIEW_STATE=permission"
  "error|--env CUE_PREVIEW_STATE=failed"
  "popover|--env CUE_PREVIEW_ACTIONS=1"
)

for mode in dark light; do
  for entry in "${STATES[@]}"; do
    label="${entry%%|*}"
    extra="${entry#*|}"
    # shellcheck disable=SC2086
    launch "$mode" --env CUE_FIXTURE_COMMANDS=finder --env CUE_FIXTURE_CONTEXT=1 --env CUE_FIXTURE_USAGE=1 \
      --env CUE_SNAPSHOT_NAME="panel-$label-$mode" $extra
    osascript -e "tell application \"$FRONT\" to activate"
    sleep 1.2
    post toggle
    sleep 2
    echo "panel-$label-$mode"
  done

  launch "$mode" --env CUE_FIXTURE_COMMANDS=finder
  for page in general appearance context privacyAndData updates about; do
    post settings "$page"
    sleep 1.6
    mv "$OUT/settings-$page.png" "$OUT/settings-$page-$mode.png"
    echo "settings-$page-$mode"
  done
done
pkill -x Cue 2>/dev/null || true
echo "done: $OUT"
