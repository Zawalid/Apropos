import AppKit
import Apropos

// Developer tool: reads an app's menu bar through the Accessibility API and optionally presses one item.
//
//   swift run apropos-probe com.apple.finder              list the commands of an app
//   swift run apropos-probe com.apple.finder --run "View > as List"   press one item
//   swift run apropos-probe --context [bundle id] [--wait 3] [--show]   print the live context snapshot
//     with no bundle id it uses the frontmost app after the wait, so switch to it; --show also prints the raw
//     URL and selection (default prints only lengths, like the app's logs)
//
// Needs Accessibility access for the terminal (or whatever launched it).

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

if arguments.first == "--context" {
    let wait = value(after: "--wait").flatMap(Double.init) ?? 0
    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    let explicit = arguments.dropFirst().first { !$0.hasPrefix("--") && Double($0) == nil }
    let running =
        explicit.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        ?? NSWorkspace.shared.frontmostApplication
    guard let running else {
        print("no application found")
        exit(1)
    }
    let app = TargetApp(
        pid: running.processIdentifier, bundleID: running.bundleIdentifier,
        name: running.localizedName ?? running.bundleIdentifier ?? "App")
    let started = Date()
    let snapshot = await ContextService().snapshot(for: app)
    let ms = Date().timeIntervalSince(started) * 1000
    let show = arguments.contains("--show")
    print(String(format: "%@ (%@) in %.0f ms, gaps: %@", app.name, app.bundleID ?? "?", ms, "\(snapshot.gaps)"))
    for item in snapshot.items { print("  [\(item.kind.rawValue)] \(item.label)  (\(item.symbol))") }
    let f = snapshot.fields
    print("  windowTitle: \(f.windowTitle ?? "-")  windows: \(f.windowCount.map(String.init) ?? "-")")
    print("  documentPath: \(f.documentPath ?? "-")  folder: \(f.folderPath ?? "-")  workspace: \(f.workspace ?? "-")")
    print("  url: \(show ? (f.url ?? "-") : (f.url == nil ? "-" : "<\(f.url?.count ?? 0) chars>"))")
    print("  selection: \(show ? (f.selectedText ?? "-") : (f.selectedText == nil ? "-" : "<\(f.selectedText?.count ?? 0) chars>"))")
    print("  selectedItems: \(f.selectedItemCount.map(String.init) ?? "-")  branch: \(f.gitBranch ?? "-")")
    exit(0)
}
guard let bundleID = arguments.first else {
    print("usage: apropos-probe <bundle id> [--run \"Menu > Item\"]")
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
