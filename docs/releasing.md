# Releasing Apropos

**Status: draft.** No release has been cut. This page describes what is meant to happen so the first one is not a
surprise. The release pipeline proper (signing, notarization, an update feed) is separate work and will replace this.

## Versions

- Semantic Versioning, `0.x` while the app is young: a feature bumps the minor number, a fix the patch.
- The version is `MARKETING_VERSION` in `App/project.yml`. The build number is the commit count
  (`git rev-list --count HEAD`).
- Every release is the tag `vX.Y.Z` on `main`. The notes come from the matching `## [X.Y.Z]` entry in
  [CHANGELOG.md](../CHANGELOG.md); entries under **Unreleased** are written by hand as work lands.

## The draft workflow

[`.github/workflows/release.yml`](../.github/workflows/release.yml) is a draft and has never run. It starts only by hand,
from the Actions tab (Release (draft), Run workflow, with the version), never on a tag or a push. It:

1. checks the input equals `MARKETING_VERSION` and that the tag does not exist yet,
2. runs `swift test`,
3. builds the Release app, signed ad hoc,
4. packs `Apropos-<version>.zip` and `Apropos-<version>.dmg` with a SHA-256 file,
5. creates a **draft pre-release** `v<version>` with those files and the changelog entry, for you to read and publish.

Publishing the draft is what creates the tag. Because the build is ad hoc signed and not notarized, the release notes tell
people to follow [install.md](install.md) for the first launch.

## Not done yet

- **Notarization.** Needs an Apple Developer Program membership and a Developer ID Application certificate. Until then,
  the first launch needs the steps in install.md.
- **In-app updates.** Apropos makes no network connections today. A Sparkle feed needs an EdDSA key pair whose private
  half lives only in repository secrets, never in the tree.
- **A first run of the workflow.** Do it once with a throwaway version on a branch before relying on it.
- **A Homebrew cask.**
