# Homebrew cask for Apropos. Lives in the tap repository Zawalid/homebrew-apropos as Casks/apropos.rb.
# `scripts/cask.sh <version>` prints this file with the version and the DMG's SHA-256 filled in.
cask "apropos" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/Zawalid/Apropos/releases/download/v#{version}/Apropos-#{version}.dmg"
  name "Apropos"
  desc "Command palette that adapts to the app in front and what you have selected"
  homepage "https://apropos.zawalid.com"

  depends_on macos: :sonoma

  app "Apropos.app"

  zap trash: [
    "~/Library/Application Support/Apropos",
    "~/Library/Caches/com.zawalid.apropos",
    "~/Library/Preferences/com.zawalid.apropos.plist",
  ]

  caveats <<~EOS
    Apropos is not signed with an Apple Developer ID yet, so macOS blocks it the first time you open it.
    Choose Open Anyway in System Settings, Privacy & Security, or run:
      xattr -dr com.apple.quarantine #{appdir}/Apropos.app
    Apropos then asks for Accessibility access to read the menus of the app in front.
  EOS
end
