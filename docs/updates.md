# Updates

Apropos can update itself, using [Sparkle](https://sparkle-project.org). It is off until you turn it on, and in a build
that has no update signing key it cannot be turned on at all.

## What it does

- **Settings, Updates, Check for updates** is off by default. When it is on, Apropos asks GitHub once a day for
  `releases/latest/download/appcast.xml`, a small file that names the newest version and where to download it.
- **Check now** (Settings, Updates, and the sparkle button in the menu bar popover) asks right away, whether or not the
  automatic check is on.
- If a newer version exists, Sparkle shows the release notes and waits. Nothing is downloaded or installed until you press
  Install Update. There is no silent installation.
- Nothing else is sent. GitHub sees the request the way it sees any download. Apropos has no account and no analytics.

This is the only time Apropos goes online by itself. The Privacy and data page of Settings says "Makes no network
connections" while it is off and "Connects only to check for updates" when it is on.

## Why an in-app update is not blocked

Apropos is not signed with an Apple Developer ID yet, so a copy downloaded from the web asks you to confirm it once.
Sparkle downloads updates itself, so the new app carries no download flag and macOS does not ask again. Each update is
checked before it is installed: the zip is signed with an EdDSA key, and the app only accepts a signature that matches the
public key inside it (`SUPublicEDKey`). An archive that was changed, or signed with another key, is refused with "The
update is improperly signed".

## The one trade-off

An app signed ad hoc (no Developer ID team) cannot load Sparkle's framework under the hardened runtime's library
validation, and crashes at launch. Apropos therefore has the entitlement
`com.apple.security.cs.disable-library-validation` (`App/AproposApp/Apropos.entitlements`), which lets it load libraries
signed by other identities. The app is not sandboxed and does not load plug-ins, and the only library it embeds is Sparkle.
The entitlement can go once the app is signed with a Developer ID.

## For the maintainer

- **Until the key exists,** `SUPublicEDKey` in `App/project.yml` is the placeholder `REPLACE_WITH_PUBLIC_KEY`. The app then
  does not start Sparkle, the toggle is disabled and Check now explains why. Nothing connects to a server.
- **Make the key pair once.** Build the app (`scripts/build-app.sh` downloads Sparkle's tools into `build/`), then run
  `build/sparkle-<version>/bin/generate_keys --account apropos` (or the copy inside DerivedData). It stores the private key in
  your login keychain and prints the public key. Put the public key in `App/project.yml` as `SUPublicEDKey`.
- **Store the private key in three places.** The login keychain, an offline backup (`generate_keys --account apropos -x
  file` exports it; keep the file in a password manager or on an encrypted drive, never in the repository), and the GitHub
  secret `SPARKLE_ED_PRIVATE_KEY` (the exported key as text).
- **Losing the private key strands every installed copy:** it could never accept an update again, and the only way out is a
  manual download. Anyone who holds the key can ship an update to every install, so it is never committed and never printed.
- `scripts/appcast.sh <version>` builds `appcast.xml` and `Apropos-<version>.zip` from `build/Apropos.app`. The release
  workflow runs it and attaches both files to the release.
- Debug builds read `APROPOS_FEED_URL` as the feed, to try an update against a local appcast without publishing one.

## Homebrew

`brew upgrade --cask apropos` keeps working and is unaffected. Pick one way of updating and stay with it.
