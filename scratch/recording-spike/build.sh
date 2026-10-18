#!/bin/sh
# Builds the throwaway fixture and harness into scratch/recording-spike/build (ignored by git).
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -O fixture/main.swift -o build/fixture
swiftc -O harness/main.swift -o build/harness
echo "built build/fixture and build/harness"
