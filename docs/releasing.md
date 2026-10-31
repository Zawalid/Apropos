# Releasing Apropos

How a new version gets from `main` to a download. One command cuts it, one push publishes it.

## Versions

- **Semantic Versioning.** `0.x` while the app is young: a new feature bumps the minor number (0.2.0), a fix bumps the
  patch (0.1.1). `1.0.0` when the settings file format and the safety model are stable.
- **One source of truth.** The version is `MARKETING_VERSION` in `App/project.yml`. `scripts/release.sh` is the only thing
  that changes it.
- **Build number.** The number of commits (`git rev-list --count HEAD`), set by `scripts/build-app.sh`. It only goes up,
  and any two builds of different commits differ. The About pane shows `Version 0.2.0 (214)`.
- **Tags.** Every release is the annotated tag `vX.Y.Z` on `main`. A tag with a dash (`v0.2.0-beta.1`) is published as a
  pre-release.

## Cutting a release

1. Make sure `main` is green (the CI workflow) and the working tree is clean.
2. Write what changed under **Unreleased** in `CHANGELOG.md` as you merge work (Added, Changed, Fixed). If you leave it
   empty, the script writes the notes from `feat:` and `fix:` commit subjects since the last tag.
3. Preview: `scripts/release.sh 0.2.0 --dry-run` prints the release notes and changes nothing.
4. Cut it: `scripts/release.sh 0.2.0`. It runs the tests, moves the Unreleased notes under `## [0.2.0]`, bumps
   `MARKETING_VERSION`, commits `chore: release v0.2.0` and tags `v0.2.0`. It never pushes.
5. Publish: `git push origin main --follow-tags`.

The tag starts [`.github/workflows/release.yml`](../.github/workflows/release.yml): it checks that the tag matches
`MARKETING_VERSION`, **waits for a green `ci.yml` run on that commit** (it does not run the tests again), builds the app,
packs `Apropos-0.2.0.dmg`, writes a SHA-256 file, builds the update feed when the Sparkle key is set, and creates a
**draft** GitHub Release with the changelog entry as its notes.

6. Try the draft: download the DMG from it and go through [install.md](install.md) on a clean account.
7. Publish it: `gh release edit v0.2.0 --draft=false`. The `releases/latest/download/...` links, the update feed and the
   Homebrew cask only work once it is published.

If the gate fails, fix the cause on `main`, let CI go green, then re-run the failed release workflow from the Actions
tab. The tag never has to move. (Moving a published tag is a destructive action and is blocked for agents.)

The workflow can also be started by hand (Actions, Release, Run workflow, with a version). That makes a draft pre-release
from the current commit and creates no tag, which is how to try the pipeline before relying on it.

## Building the same thing locally

```bash
scripts/build-app.sh      # build/Apropos.app, ad hoc signed (SIGN_IDENTITY="Developer ID Application: ..." to sign)
scripts/make-dmg.sh       # build/Apropos.dmg: dark installer window, the app and an Applications shortcut
```

`make-dmg.sh` uses [dmgbuild](https://github.com/dmgbuild/dmgbuild) in a throwaway virtualenv under `build/`, so it needs
no Finder scripting and runs on CI. The window art is `scripts/dmg/background.tiff`; edit `scripts/dmg/background.html`
and regenerate it with `node scripts/dmg/render-background.mjs` (needs `npm i --no-save playwright-core` and a Chromium).

## Signing and notarization

Today the app is ad hoc signed, so users do the one-time first-launch step in [install.md](install.md). To remove it you
need an Apple Developer Program membership (99 USD a year) and a **Developer ID Application** certificate. Add these
repository secrets and the same workflow signs and notarizes with no other change:

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12` | the certificate and private key exported as a `.p12`, base64 encoded |
| `DEVELOPER_ID_P12_PASSWORD` | the `.p12` password |
| `DEVELOPER_ID_NAME` | `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_KEY_P8` | an App Store Connect API key (`.p8`), base64 encoded |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | that key's id and the issuer id |

The signing and notarization steps have not been run yet; the first signed release is the test, so cut a pre-release
(`0.2.0-beta.1`) first.

## Homebrew

Create the repository `Zawalid/homebrew-apropos` once (public, with a README that says what it is). After each release,
as soon as the release workflow has finished:

```bash
mkdir -p ../homebrew-apropos/Casks
scripts/cask.sh 0.2.0 > ../homebrew-apropos/Casks/apropos.rb
cd ../homebrew-apropos && git add -A && git commit -m "apropos 0.2.0" && git push
```

People install with two commands, because current Homebrew refuses to load a cask from a third-party tap until it is
trusted: `brew trust zawalid/apropos`, then `brew install --cask zawalid/apropos/apropos`. The cask template is
[`packaging/homebrew/apropos.rb`](../packaging/homebrew/apropos.rb); its caveat tells people about the first-launch step
until the app is notarized. The cask does not declare `auto_updates`, so Homebrew keeps upgrading it; pick one way of
updating and stay with it.

## In-app updates

Each release also publishes `appcast.xml` and `Apropos-<version>.zip` (see [updates.md](updates.md)). The workflow builds
them with `scripts/appcast.sh` when the repository secret `SPARKLE_ED_PRIVATE_KEY` is set; without it the release still
publishes, just with no update feed. Check after a release that `releases/latest/download/appcast.xml` opens.

## The first release, in order

1. Generate the Sparkle key pair and put the public key in `App/project.yml` (see [updates.md](updates.md)).
2. Add `SPARKLE_ED_PRIVATE_KEY` as a repository secret, and keep an offline backup of the key.
3. Run the workflow by hand once for a draft pre-release and download the DMG on a clean Mac or user account.
4. Cut `0.1.0` with `scripts/release.sh 0.1.0`, push the tag, try the draft, publish it.
5. Create the tap and publish the cask with `scripts/cask.sh`.

## Later

- Automating the cask update from the release workflow.
- Notarization, when there is a Developer ID.
