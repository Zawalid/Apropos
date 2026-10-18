import Testing

@testable import Apropos

struct CommandDisplayTests {
    private func command(_ title: String, path: [String] = ["File"]) -> Command {
        Command(id: title, title: title, path: path, source: .menuItem(bundleID: nil))
    }

    @Test func stripsTrailingEllipsis() {
        #expect(CommandDisplay.cleanTitle("Open\u{2026}") == "Open")
        #expect(CommandDisplay.cleanTitle("Save As...") == "Save As")
        #expect(CommandDisplay.cleanTitle("Open Recent \u{2026}") == "Open Recent")
    }

    @Test func stripsUpdateSuffix() {
        #expect(CommandDisplay.cleanTitle("App Store, 1 update") == "App Store")
        #expect(CommandDisplay.cleanTitle("Software Update, 12 updates\u{2026}") == "Software Update")
    }

    @Test func keepsPlainTitles() {
        #expect(CommandDisplay.cleanTitle("New Session") == "New Session")
        #expect(CommandDisplay.cleanTitle("\u{2026}") == "\u{2026}")
    }

    @Test func subtitleShowsMenuPathNotAppName() {
        #expect(command("New Session", path: ["File"]).displaySubtitle(appName: "Xcode") == "File")
        #expect(command("X", path: ["File", "New"]).displaySubtitle(appName: "Xcode") == "File > New")
        #expect(command("About", path: ["Xcode"]).displaySubtitle(appName: "Xcode") == "App menu")
    }

    @Test func symbolsFollowVerbThenMenu() {
        #expect(CommandDisplay.symbol(for: command("Open Recent")) == "folder")
        #expect(CommandDisplay.symbol(for: command("Whatever", path: ["View"])) == "eye")
        #expect(CommandDisplay.symbol(for: command("Whatever", path: ["Odd"])) == "command")
    }
}

struct AmbiguousTitleTests {
    @Test func lowerCaseAndGenericTitlesNeedTheirMenu() {
        #expect(CommandDisplay.isAmbiguous(title: "as Columns"))
        #expect(CommandDisplay.isAmbiguous(title: "Reset"))
        #expect(!CommandDisplay.isAmbiguous(title: "New Finder Window"))
        #expect(!CommandDisplay.isAmbiguous(title: "Empty Trash"))
    }
}
