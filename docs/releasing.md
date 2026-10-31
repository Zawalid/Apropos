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

The workflow can also be started by hand (Actions, Release, Run workflow). That is a trial: it builds the current branch
as a throwaway draft pre-release under a `test-N` tag, which is how to try the pipeline, and the signing, before a real
release. Delete the trial draft afterwards.

## Building the same thing locally

```bash
scripts/build-app.sh      # build/Apropos.app, ad hoc signed (SIGN_IDENTITY="Developer ID Application: ..." to sign)
scripts/make-dmg.sh       # build/Apropos.dmg: dark installer window, the app and an Applications shortcut
```

`make-dmg.sh` uses [dmgbuild](https://github.com/dmgbuild/dmgbuild) in a throwaway virtualenv under `build/`, so it needs
no Finder scripting and runs on CI. The window art is `scripts/dmg/background.tiff`; edit `scripts/dmg/background.html`
and regenerate it with `node scripts/dmg/render-background.mjs` (needs `npm i --no-save playwright-core` and a Chromium).

## Signing and notarization

There are three levels, and each needs only repository secrets, no workflow change.

1. **Ad hoc (no secrets).** What a build gets by default. It runs, but its signature is only a hash of that one build, so
   macOS treats every update as a different app and **drops the Accessibility grant**. People also do the first-launch
   step in [install.md](install.md).
2. **A stable certificate (free, recommended now).** Run `scripts/make-signing-cert.sh` once. It makes a self-signed code
   signing certificate in `~/.apropos-secrets/` and prints the three `gh secret set` commands. Every release is then signed
   with the same certificate, the app keeps its identity (`identifier ... and certificate leaf = ...`), and the
   Accessibility grant survives updates. The first-launch step stays, because the certificate is not Apple's. The workflow
   trusts the certificate on the runner for code signing and prints the app's designated requirement so you can see it.
3. **Developer ID and notarization (later).** Needs an Apple Developer Program membership (99 USD a year). Use that
   certificate in the same three secrets and add the notarization secrets. The first-launch step goes away.

| Secret | What |
|---|---|
| `SIGNING_P12` | the certificate and private key as a `.p12`, base64 encoded |
| `SIGNING_P12_PASSWORD` | the `.p12` password |
| `SIGNING_IDENTITY` | the certificate's name, for example `Apropos Release` or `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_KEY_P8` | an App Store Connect API key (`.p8`), base64 encoded (level 3 only) |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | that key's id and the issuer id (level 3 only) |

Keep the certificate's private key like the Sparkle key: it lives in the secrets and in an offline backup. If it is lost, a
new certificate is a new identity and every install re-grants Accessibility once. Switching from ad hoc to a certificate
does the same, once. Library validation stays off (see [updates.md](updates.md)) until a Developer ID certificate is used.

None of the signing steps has run yet. Try them with a draft: set the secrets, run the Release workflow by hand, download
the DMG and check `codesign -d -r- Apropos.app` shows the certificate and not a cdhash.

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

0. Run `scripts/make-signing-cert.sh` and set the three signing secrets (see above), so the first release already keeps
   its identity across updates.
1. Generate the Sparkle key pair and put the public key in `App/project.yml` (see [updates.md](updates.md)).
2. Add `SPARKLE_ED_PRIVATE_KEY` as a repository secret, and keep an offline backup of the key.
3. Run the workflow by hand once for a draft pre-release and download the DMG on a clean Mac or user account.
4. Cut `0.1.0` with `scripts/release.sh 0.1.0`, push the tag, try the draft, publish it.
5. Create the tap and publish the cask with `scripts/cask.sh`.

## Later

- Automating the cask update from the release workflow.
- Notarization, when there is a Developer ID.
