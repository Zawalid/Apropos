import Foundation

/// A name for a throwaway defaults suite whose plist lives in the temporary folder. A plain name such as "apropos.test.1"
/// would leave a file in ~/Library/Preferences on every test run, because macOS keeps the plist after the domain is cleared
/// and writes it again a moment later. A suite named by a full path keeps its plist at that path instead.
func scratchDefaultsSuite(_ label: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("apropos-\(label)-\(UUID().uuidString)").path
}
