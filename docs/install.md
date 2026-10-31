# Installing Apropos

Apropos needs **macOS 14 (Sonoma) or later**. There is no signed or notarized release yet, so this page is honest about
what that means for you.

## Status of the download

- There is no release asset on GitHub yet. Until there is, build from source (below). Once there is one, a download
  is `Apropos-<version>.dmg` from the Releases page (`releases/latest/download/Apropos.dmg` always points at the newest),
  and Homebrew installs it (see [With Homebrew](#with-homebrew)).
- The first downloadable builds will **not be notarized**. Notarization needs an Apple Developer Program membership, and
  there is no account behind the project at the moment. When that changes, this page and the releases will say so.
- A build you make yourself on your own Mac is signed ad hoc by Xcode and opens without any of the steps in
  [The first launch of a downloaded build](#the-first-launch-of-a-downloaded-build).

## With Homebrew

Current Homebrew refuses to load a cask from a tap that is not Homebrew's own until you trust it. Two commands:

```bash
brew trust zawalid/apropos
```

```bash
brew install --cask zawalid/apropos/apropos
```

The first launch still needs the steps in [The first launch of a downloaded build](#the-first-launch-of-a-downloaded-build),
until the app is notarized. Update with `brew upgrade --cask apropos`.

## Build from source

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/Zawalid/Apropos.git
cd Apropos
(cd App && xcodegen generate)
xcodebuild build -project App/Apropos.xcodeproj -scheme Apropos -configuration Release \
  -derivedDataPath build/release CODE_SIGN_IDENTITY="-"
```

The app is at `build/release/Build/Products/Release/Apropos.app`. Drag it to Applications and open it.

## The first launch of a downloaded build

A build that came through a browser, a chat app or AirDrop carries the macOS quarantine flag. For an app that is neither
signed with an Apple Developer ID nor notarized, Gatekeeper cannot ask Apple whether it is known, so it refuses to open
it the first time ("Apple could not verify Apropos is free of malware"). That message is about the missing notarization,
not a finding about the app. You confirm once and macOS remembers.

1. Open Apropos from Applications. When the warning appears, click **Done**. Do not choose Move to Trash.
2. Open **System Settings**, then **Privacy & Security**, and scroll to the Security section. It says Apropos was
   blocked. Click **Open Anyway**, confirm with your password or Touch ID, then **Open**.

On macOS 15 (Sequoia) and later this is the only supported way in: right-click, Open no longer skips the check there. On
macOS 14 you can also right-click Apropos in Applications, choose **Open**, then **Open** again.

Prefer the Terminal? This removes the quarantine flag, which is what the warning is triggered by:

```bash
xattr -dr com.apple.quarantine /Applications/Apropos.app
```

Only do this for a build whose source you trust. When a release exists, check the download against its `.sha256` file
first:

```bash
shasum -a 256 -c Apropos-<version>.dmg.sha256
```

Apropos is open source, so you can read what it does or build it yourself instead.

## Permissions

On first launch a welcome guide asks for **Accessibility** access and opens the right page of System Settings. Apropos
needs it to read and press the menu items of the app in front. Nothing else is requested until you use a feature that
needs it: Input Monitoring for recording a command, and Automation the first time one of your commands controls another
app. What each permission is used for is on the Privacy and data page of Settings.

macOS ties the Accessibility grant to the app's code signature. An ad hoc signature changes on every build, so after you
rebuild from source macOS may show an entry that looks enabled but no longer works. Remove it with the minus button in
System Settings, Privacy & Security, Accessibility, and let Apropos add itself again. To keep the grant across rebuilds,
sign with a stable certificate (see [development.md](development.md)).

## Updating

Apropos can update itself, but only if you turn it on (Settings, Updates). It then asks GitHub once a day whether a newer
version exists, shows what is new and waits for you to press Install Update. It is off by default, and a build without an
update signing key cannot turn it on. See [updates.md](updates.md). Otherwise download the new version and replace the app,
or run `brew upgrade --cask apropos`. Your settings and commands are kept between versions.

## Uninstalling

Quit Apropos from its menu bar icon and move it to the Trash. To remove its data as well:

```bash
rm -r ~/Library/Application\ Support/Apropos
defaults delete com.zawalid.apropos
```

If you used the app under its former name, Cue, the old folder `~/Library/Application Support/Cue` is still there (it is
never changed or deleted) and can be removed the same way.

## Where Apropos keeps things

| What | Where |
|---|---|
| Settings | `~/Library/Application Support/Apropos/settings.json` |
| Your commands | `~/Library/Application Support/Apropos/commands/` |
| Usage, pins and aliases | `~/Library/Application Support/Apropos/usage.json` |
| Order commands ran in (for Usually next) | `~/Library/Application Support/Apropos/sequence.json` |
| Preferences | `~/Library/Preferences/com.zawalid.apropos.plist` |

Apropos never sends any of this anywhere. See [data-layer.md](data-layer.md) and the threat model in
[SECURITY.md](../SECURITY.md).
