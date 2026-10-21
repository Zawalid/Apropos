#!/usr/bin/env bash
# Prints the Homebrew cask for a published release, with its checksum filled in.
#
#   scripts/cask.sh 0.2.0 > ../homebrew-apropos/Casks/apropos.rb
#
# It downloads the release's DMG checksum file from GitHub, so run it after the release workflow has finished.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/cask.sh <version>}"
SHA="$(curl -fsSL "https://github.com/Zawalid/Apropos/releases/download/v$VERSION/Apropos-$VERSION.dmg.sha256" | cut -d' ' -f1)"
[ -n "$SHA" ] || { echo "no checksum found for v$VERSION" >&2; exit 1; }
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/homebrew/apropos.rb
