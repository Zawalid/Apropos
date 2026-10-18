#!/bin/sh
# Runs the recording spike experiments against the throwaway fixture only. Read docs/recording-spike.md first.
#
# Prerequisite (only Walid can do this): System Settings > Privacy & Security > Accessibility > add the terminal app
# you run this script from (or the absolute path of build/harness), and for the event tap section also
# Privacy & Security > Input Monitoring. Then run:  scripts below, from scratch/recording-spike:  ./run-experiments.sh
#
# The fixture is an accessory app with a transparent, mouse-transparent window: it never takes focus and shows nothing.
set -e
cd "$(dirname "$0")"
./build.sh
OUT=build/results; mkdir -p "$OUT"
./build/harness preflight | tee "$OUT/preflight.txt"

run_locale() {  # $1 = en|fr, $2 = steps file
  if [ "$1" = fr ]; then ./build/fixture -AppleLanguages "(fr)" > "$OUT/fixture-$1.log" & else ./build/fixture > "$OUT/fixture-$1.log" & fi
  PID=$!; sleep 1.5
  echo "== $1: tree"; ./build/harness dump $PID | tee "$OUT/tree-$1.txt"
  echo "== $1: replay"; ./build/harness replay $PID "$2" | tee "$OUT/replay-$1.txt" || true
  sleep 0.5; echo "== $1: fixture saw"; cat "$OUT/fixture-$1.log"
  kill $PID
}
run_locale en steps-en.json
run_locale fr steps-en.json     # the English-title steps replayed on the French UI: shows what breaks without identifiers

# Observation: start the observer, then drive the fixture with the replay (programmatic actions) for 8 seconds.
./build/fixture > "$OUT/fixture-obs.log" & PID=$!; sleep 1.5
./build/harness observe $PID 8 > "$OUT/observe.txt" & OBS=$!; sleep 1
./build/harness replay $PID steps-en.json > /dev/null || true
wait $OBS || true; kill $PID
echo "== observe"; cat "$OUT/observe.txt"
echo "Results are in $OUT. Paste them back to the session or into docs/recording-spike.md."
