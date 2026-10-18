import AppKit
import Cue

// Developer tool: reads an app's menu bar through the Accessibility API and optionally presses one item.
//
//   swift run cue-probe com.apple.finder              list the commands of an app
//   swift run cue-probe com.apple.finder --run "View > as List"   press one item
//
// Needs Accessibility access for the terminal (or whatever launched it).

let arguments = Array(CommandLine.arguments.dropFirst())
guard let bundleID = arguments.first else {
    print("usage: cue-probe <bundle id> [--run \"Menu > Item\"]")
    exit(2)
}
guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("\(bundleID) is not running")
    exit(1)
}

do {
    let started = Date()
    let bar = try AXMenuReader().readMenuBar(pid: running.processIdentifier)
    let commands = MenuCommandMapper.commands(from: bar, bundleID: bundleID)
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "%@: %d commands in %.0f ms", bundleID, commands.count, elapsed * 1000))

    if let flag = arguments.firstIndex(of: "--run"), arguments.indices.contains(flag + 1) {
        let wanted = arguments[flag + 1].split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let match = commands.first(where: { $0.path + [$0.title] == wanted }) else {
            print("no command at \(wanted.joined(separator: " > "))")
            exit(1)
        }
        try match.target?.perform()
        print("pressed \(wanted.joined(separator: " > "))")
    } else {
        for command in commands {
            let flags = (command.isEnabled ? "" : " [disabled]") + (command.isChecked ? " [checked]" : "")
            print("\(command.breadcrumb) › \(command.title)\(command.shortcut.map { "  \($0.display)" } ?? "")\(flags)")
        }
    }
} catch let error as MenuReadError {
    print("could not read menus: \(error.message)")
    exit(1)
} catch {
    print("failed: \(error)")
    exit(1)
}
