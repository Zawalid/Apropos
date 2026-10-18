#!/usr/bin/env bash
# Draws every preview scene (App/AproposApp/Preview/Previews.swift) to PNGs in build/previews/, dark and light, without
# opening the app, a window or Xcode's canvas.
#
#   scripts/render-previews.sh                     build once, render everything
#   scripts/render-previews.sh --no-build          reuse the last build
#   scripts/render-previews.sh palette-finder ...  render only the named scenes (ids are the file name prefixes)
#
# It builds the AproposPreviewRender command line tool into build/agent, the same folder scripts/shots.sh uses, so it takes
# the same lock and never overlaps with a shots run. The tool is its own process: it does not touch the copy you run
# with scripts/dev.sh and needs neither Accessibility access nor code signing. The glass shows no real desktop behind
# it, so check glass in the real app.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="build/agent/Build/Products/Debug/AproposPreviewRender"
OUT="$PWD/build/previews"
LOCK="build/shots.lock"
BUILD=1
if [ "${1:-}" = "--no-build" ]; then
  BUILD=0
  shift
fi

mkdir -p build "$OUT"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "another run is using build/agent ($LOCK exists); wait for it or remove the lock if it crashed"
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

if [ "$BUILD" = 1 ]; then
  (cd App && xcodegen generate >/dev/null)
  if ! xcodebuild build -project App/Apropos.xcodeproj -scheme AproposPreviewRender -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath build/agent -quiet 2>build/agent-errors.log; then
    echo "build failed:"
    grep -E "error:" build/agent-errors.log | head -10
    exit 1
  fi
fi

"$BIN" "$OUT" "$@"
echo "done: $OUT"
