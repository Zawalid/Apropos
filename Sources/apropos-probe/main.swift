import AppKit
import Apropos

// Developer tool: reads an app's menu bar through the Accessibility API and optionally presses one item.
//
//   swift run apropos-probe com.apple.finder              list the commands of an app
//   swift run apropos-probe com.apple.finder --run "View > as List"   press one item
//   swift run apropos-probe --context [bundle id] [--wait 3] [--show]   print the live context snapshot
//     with no bundle id it uses the frontmost app after the wait, so switch to it; --show also prints the raw
//     URL and selection (default prints only lengths, like the app's logs)
//   swift run apropos-probe --actions [bundle id] [--wait 3] [--all]   print the context actions that apply now
//     same app selection as --context; --all also lists the actions that do not apply and why
//   swift run apropos-probe --predict-eval [--file path] [--synthetic [days]] [--train 0.5]
//       [--noise 0.06] [--interleave 0.12] [--pseudo 2] [--smoothing 0.5] [--half-life 30]   model settings, for tuning
//     replays the run log (default: the real local one) chronologically, trains on the past, tests on the future and
//     prints aggregate numbers only: hit rates, coverage, calibration. Never prints a command name. --synthetic uses a
//     generated log instead, so the numbers in docs/prediction.md can be reproduced.
//
// Needs Accessibility access for the terminal (or whatever launched it).

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

if arguments.first == "--predict-eval" {
    var events: [RunEvent]
    var source: String
    if let index = arguments.firstIndex(of: "--synthetic") {
        var profile = SyntheticProfile()
        if arguments.indices.contains(index + 1), let days = Int(arguments[index + 1]) { profile.days = days }
        profile.driftDay = profile.days * 2 / 3
        if let noise = value(after: "--noise").flatMap(Double.init) { profile.noise = noise }
        if let interleave = value(after: "--interleave").flatMap(Double.init) { profile.interleave = interleave }
        events = SyntheticLog.generate(profile)
        source = "synthetic, \(profile.days) days, habits change on day \(profile.driftDay ?? 0)"
    } else {
        let url = value(after: "--file").map { URL(fileURLWithPath: $0) } ?? SequenceLog.url(besides: UsageStore.defaultURL)
        events = SequenceLog.readEvents(from: url)
        source = "local run log"
    }
    var evaluator = PredictionEvaluator()
    if let pseudo = value(after: "--pseudo").flatMap(Double.init) { evaluator.settings.pseudoCount = pseudo }
    if let smoothing = value(after: "--smoothing").flatMap(Double.init) { evaluator.settings.smoothing = smoothing }
    if let half = value(after: "--half-life").flatMap(Double.init) { evaluator.settings.halfLifeDays = half }
    if let fraction = value(after: "--train").flatMap(Double.init) { evaluator.trainFraction = fraction }
    guard events.count >= 100 else {
        print("\(source): \(events.count) events, too few to evaluate (need at least 100)")
        exit(events.isEmpty ? 1 : 0)
    }
    let span = (events.last?.time ?? 0) - (events.first?.time ?? 0)
    print("source: \(source), \(events.count) events over \(Int(span / 86_400)) days")
    print(evaluator.run(events).render())
    exit(0)
}

if arguments.first == "--context" || arguments.first == "--actions" {
    let listActions = arguments.first == "--actions"
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
    if listActions {
        let library = ActionPackLibrary.bundled(plus: ActionPackLibrary.userDirectory)
        print(String(format: "%@ (%@) in %.0f ms, gaps: %@", app.name, app.bundleID ?? "?", ms, "\(snapshot.gaps)"))
        if snapshot.gaps.contains(.notTrusted) {
            print("  no Accessibility access for this terminal, so no context was read; grant it to the terminal and retry")
        }
        print("  context: \(snapshot.values)")
        let applicable = library.applicable(to: snapshot.values, bundleID: app.bundleID)
        for group in ActionGroup.allCases {
            let inGroup = applicable.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            print("  \(group.title)")
            for action in inGroup { print("    \(action.id.rawValue)  \(action.title)  -> \(action.output.rawValue)") }
        }
        if applicable.isEmpty { print("  no actions apply") }
        if arguments.contains("--all") {
            for action in library.actions where !applicable.contains(where: { $0.id == action.id }) {
                let missing = action.requires.filter { !snapshot.values.has($0) }.map(\.rawValue).sorted()
                let reason = missing.isEmpty ? "condition or app filter" : "needs " + missing.joined(separator: ", ")
                print("  [off] \(action.id.rawValue)  (\(reason))")
            }
        }
        for issue in library.issues {
            print("  [skipped] \(issue.source) \(issue.actionID ?? "-"): \(issue.reason)")
        }
        exit(0)
    }
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
