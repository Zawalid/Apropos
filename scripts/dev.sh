#!/usr/bin/env bash
# Fast development loop: quit the running app, rebuild a Debug build, relaunch it.
#
#   scripts/dev.sh            build and open once
#   scripts/dev.sh --watch    keep running: save a file under App/ or Sources/ and the app relaunches
#   scripts/dev.sh --logs     build, open, then stream the app's log output
#
# Builds go to build/dev (ignored by git), so the app path is stable and Xcode's own build is untouched.
#
# Cue needs Accessibility access, and macOS ties that grant to the app's code signature. An ad hoc signature changes
# on every build, so the grant would be lost each time and the welcome screen would come back. After each build this
# script re-signs the app with a stable identity: CUE_SIGN_IDENTITY if set, otherwise the first code signing
# certificate in your keychain (see `security find-identity -v -p codesigning`). With no certificate it falls back to
# ad hoc and says so. Grant Accessibility once to the app this script builds; it then survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/dev/Build/Products/Debug/Apropos.app"
MODE="${1:-once}"
IDENTITY="${CUE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^ *1) [0-9A-F]* "\(.*\)"$/\1/p')"
fi

build_and_open() {
  local started=$SECONDS
  (cd App && xcodegen generate >/dev/null)
  if ! xcodebuild build \
      -project App/Apropos.xcodeproj -scheme Apropos -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath build/dev -quiet \
      CODE_SIGN_IDENTITY="-" 2>build/dev-errors.log; then
    echo "build failed:"
    grep -E "error:" build/dev-errors.log | head -10
    return 1
  fi
  if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || echo "re-signing with '$IDENTITY' failed; the app is ad hoc signed"
  else
    echo "no code signing identity found: the app is ad hoc signed and Accessibility must be re-granted after each build"
  fi
  # Stops only the copy this script builds, never an agent run from build/agent.
  pkill -f "$PWD/$APP/Contents/MacOS/Apropos" 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "relaunched in $((SECONDS - started))s"
}

# A fingerprint of every source file the app depends on; changes when anything is saved.
fingerprint() {
  find App/AproposApp Sources/Apropos \( -name '*.swift' -o -name '*.yml' -o -name '*.json' \) 2>/dev/null \
    | sort | xargs stat -f '%N %m' 2>/dev/null | shasum | cut -d' ' -f1
}

mkdir -p build
case "$MODE" in
  --watch)
    build_and_open || true
    last="$(fingerprint)"
    echo "watching for changes (Ctrl-C to stop)"
    while true; do
      sleep 1
      now="$(fingerprint)"
      if [ "$now" != "$last" ]; then
        last="$now"
        echo "change detected"
        build_and_open || true
      fi
    done
    ;;
  --logs)
    build_and_open
    exec /usr/bin/log stream --style compact --predicate 'process == "Apropos"'
    ;;
  *)
    build_and_open
    ;;
esac
