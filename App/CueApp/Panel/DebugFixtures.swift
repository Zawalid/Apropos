#if DEBUG
    import Cue

    /// Debug builds only: CUE_FIXTURE_COMMANDS=finder|safari|xcode seeds a realistic command list so the palette can be
    /// checked without Accessibility access. Titles keep the noise real menus carry (ellipses, update counts).
    enum DebugFixtures {
        static func commands(named name: String) -> [Command] {
            let spec: [(path: [String], title: String, key: KeyShortcut?, enabled: Bool, checked: Bool)]
            let cmd = ModifierSet.command
            switch name {
            case "safari":
                spec = [
                    (["File"], "New Window", KeyShortcut(key: "N", modifiers: cmd), true, false),
                    (["File"], "New Private Window", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false),
                    (["File"], "Open File\u{2026}", KeyShortcut(key: "O", modifiers: cmd), true, false),
                    (["File"], "Close Tab", KeyShortcut(key: "W", modifiers: cmd), true, false),
                    (["File"], "Share\u{2026}", nil, true, false),
                    (["Edit"], "Find\u{2026}", KeyShortcut(key: "F", modifiers: cmd), true, false),
                    (["View"], "Show Sidebar", KeyShortcut(key: "S", modifiers: [.shift, cmd]), true, true),
                    (["View"], "Enter Reader", KeyShortcut(key: "R", modifiers: [.shift, cmd]), true, false),
                    (
                        ["History"], "Reopen Last Closed Tab", KeyShortcut(key: "T", modifiers: [.shift, cmd]), true,
                        false
                    ),
                    (["Bookmarks"], "Add Bookmark\u{2026}", KeyShortcut(key: "D", modifiers: cmd), true, false),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                    (["Window"], "Software Update, 1 update", nil, false, false),
                ]
            case "xcode":
                spec = [
                    (
                        ["File", "New"], "Project\u{2026}", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false
                    ),
                    (["File"], "Open Quickly\u{2026}", KeyShortcut(key: "O", modifiers: [.shift, cmd]), true, false),
                    (
                        ["Edit"], "Find in Project\u{2026}", KeyShortcut(key: "F", modifiers: [.shift, cmd]), true,
                        false
                    ),
                    (
                        ["Navigate"], "Jump to Definition", KeyShortcut(key: "J", modifiers: [.control, cmd]), true,
                        false
                    ),
                    (["Editor"], "Re-Indent", KeyShortcut(key: "I", modifiers: .control), true, false),
                    (["Product"], "Run", KeyShortcut(key: "R", modifiers: cmd), true, false),
                    (["Product"], "Test", KeyShortcut(key: "U", modifiers: cmd), true, false),
                    (["Product"], "Clean Build Folder", KeyShortcut(key: "K", modifiers: [.shift, cmd]), true, false),
                    (["Debug"], "Pause", KeyShortcut(key: "Y", modifiers: [.control, cmd]), false, false),
                    (
                        ["Source Control"], "Commit\u{2026}", KeyShortcut(key: "C", modifiers: [.option, cmd]), true,
                        false
                    ),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                ]
            default:
                spec = [
                    (["File"], "New Finder Window", KeyShortcut(key: "N", modifiers: cmd), true, false),
                    (["File"], "New Folder", KeyShortcut(key: "N", modifiers: [.shift, cmd]), true, false),
                    (["File"], "Get Info", KeyShortcut(key: "I", modifiers: cmd), true, false),
                    (["File"], "Compress 3 Items", nil, true, false),
                    (["Edit"], "Copy 3 Items", KeyShortcut(key: "C", modifiers: cmd), true, false),
                    (["View"], "as Columns", KeyShortcut(key: "3", modifiers: cmd), true, true),
                    (["View"], "Show Path Bar", KeyShortcut(key: "P", modifiers: [.option, cmd]), true, false),
                    (["Go"], "Enclosing Folder", KeyShortcut(key: "\u{2191}", modifiers: cmd), true, false),
                    (["Go"], "Go to Folder\u{2026}", KeyShortcut(key: "G", modifiers: [.shift, cmd]), true, false),
                    (["Window"], "Minimize", KeyShortcut(key: "M", modifiers: cmd), true, false),
                    (["Help"], "Finder Help", KeyShortcut(key: "?", modifiers: cmd), true, false),
                ]
            }
            return spec.enumerated().map { index, item in
                Command(
                    id: "fx-\(index)", title: item.title, path: item.path, shortcut: item.key, isEnabled: item.enabled,
                    isChecked: item.checked, source: .menuItem(bundleID: nil))
            }
        }
    }
#endif
