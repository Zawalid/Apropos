// Throwaway harness for the recording spike. It talks to the fixture app only (pass the fixture's pid).
//
//   harness preflight                  which permissions this process has (no prompt is shown)
//   harness dump <pid>                 print the fixture's accessibility tree with every addressing attribute
//   harness observe <pid> <seconds>    print AX notifications and an event tap summary while a human or script drives it
//   harness replay <pid> <steps.json>  replay recorded steps with ordered locator fallbacks, report timing and failures
//
// It never prompts for permission, never activates an app and refuses to run against anything but a process whose
// executable name is "fixture".
import AppKit
import ApplicationServices

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

// MARK: attribute helpers
func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &out) == .success ? out : nil
}
func str(_ e: AXUIElement, _ name: String) -> String? { attr(e, name) as? String }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))"
}
func isSecure(_ e: AXUIElement) -> Bool { str(e, kAXSubroleAttribute) == "AXSecureTextField" }

func appElement(_ pid: pid_t) -> AXUIElement {
    guard let app = NSRunningApplication(processIdentifier: pid), app.executableURL?.lastPathComponent == "fixture" else {
        fail("pid \(pid) is not the fixture app. Refusing.")
    }
    let el = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(el, 1.5)
    return el
}
func requireTrust() { if !AXIsProcessTrusted() { fail("BLOCKED: this process is not trusted for Accessibility. See docs/recording-spike.md, section Running the blocked experiments.") } }

// MARK: dump
func dump(_ e: AXUIElement, depth: Int) {
    guard depth < 10 else { return }
    let secure = isSecure(e)
    let value = secure ? "<withheld>" : (str(e, kAXValueAttribute) ?? "")
    print(String(repeating: "  ", count: depth)
        + "\(str(e, kAXRoleAttribute) ?? "?")/\(str(e, kAXSubroleAttribute) ?? "-") id=\"\(str(e, "AXIdentifier") ?? "")\" title=\"\(str(e, kAXTitleAttribute) ?? "")\" desc=\"\(str(e, kAXDescriptionAttribute) ?? "")\" value=\"\(value.prefix(40))\" \(frame(e))")
    for c in kids(e) { dump(c, depth: depth + 1) }
}

// MARK: locators with ordered fallbacks
struct Locator: Codable {
    var role: String?
    var identifier: String?
    var title: String?
    var description: String?
    var menuPath: [String]?   // for menu items: titles from the menu bar down
}
struct Step: Codable {
    var kind: String          // press | setValue | menu
    var locator: Locator
    var value: String?
}

func search(_ root: AXUIElement, limit: Int = 600, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var queue = [root], seen = 0
    while !queue.isEmpty, seen < limit {
        let e = queue.removeFirst(); seen += 1
        if match(e) { return e }
        queue += kids(e)
    }
    return nil
}

/// Returns the element and the name of the strategy that found it. Order is the order of trust.
func resolve(_ l: Locator, in app: AXUIElement) -> (AXUIElement, String)? {
    if let path = l.menuPath, let bar = attr(app, kAXMenuBarAttribute) {
        var node = bar as! AXUIElement
        for title in path {
            guard let next = search(node, limit: 200, { str($0, kAXTitleAttribute) == title && str($0, kAXRoleAttribute)?.hasPrefix("AXMenu") == true && str($0, kAXRoleAttribute) != "AXMenu" }) else { return nil }
            node = next
        }
        return (node, "menuPath")
    }
    var strategies: [(String, (AXUIElement) -> Bool)] = []
    if let id = l.identifier { strategies.append(("identifier", { str($0, "AXIdentifier") == id })) }
    if let role = l.role, let t = l.title { strategies.append(("role+title", { str($0, kAXRoleAttribute) == role && str($0, kAXTitleAttribute) == t })) }
    if let role = l.role, let d = l.description { strategies.append(("role+description", { str($0, kAXRoleAttribute) == role && str($0, kAXDescriptionAttribute) == d })) }
    for (name, match) in strategies { if let e = search(app, match) { return (e, name) } }
    return nil
}

func frontmostName() -> String { NSWorkspace.shared.frontmostApplication?.localizedName ?? "?" }

func replay(_ pid: pid_t, _ file: String) {
    requireTrust()
    let app = appElement(pid)
    guard let data = FileManager.default.contents(atPath: file), let steps = try? JSONDecoder().decode([Step].self, from: data) else { fail("cannot read steps") }
    let frontBefore = frontmostName()
    for (i, step) in steps.enumerated() {
        let start = Date()
        var found: (AXUIElement, String)?
        while Date().timeIntervalSince(start) < 3 {            // wait for the UI: poll, never sleep blindly
            found = resolve(step.locator, in: app)
            if found != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let (el, strategy) = found else { print("step \(i) \(step.kind): FAIL not found after 3s"); continue }
        let status: AXError
        switch step.kind {
        case "setValue":
            if isSecure(el) { print("step \(i): REFUSED secure field"); continue }
            status = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, (step.value ?? "") as CFString)
        default:
            status = AXUIElementPerformAction(el, kAXPressAction as CFString)
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("step \(i) \(step.kind): \(status == .success ? "ok" : "AXError \(status.rawValue)") via \(strategy) in \(ms) ms")
    }
    print("frontmost app before: \(frontBefore), after: \(frontmostName())")
}

// MARK: observe
let notifications = [
    kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXValueChangedNotification,
    kAXSelectedRowsChangedNotification, kAXSelectedTextChangedNotification, kAXWindowCreatedNotification,
    kAXSheetCreatedNotification, kAXMenuOpenedNotification, kAXMenuClosedNotification, kAXMenuItemSelectedNotification,
    kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXApplicationActivatedNotification,
]
let observerCallback: AXObserverCallback = { _, element, name, _ in
    let secure = isSecure(element)
    print("AX \(name as String) role=\(str(element, kAXRoleAttribute) ?? "?") id=\(str(element, "AXIdentifier") ?? "") title=\(str(element, kAXTitleAttribute) ?? "")\(secure ? " [secure: value withheld]" : "")")
    fflush(stdout)
}
func observe(_ pid: pid_t, seconds: Double) {
    requireTrust()
    let app = appElement(pid)
    var observer: AXObserver?
    guard AXObserverCreate(pid, observerCallback, &observer) == .success, let observer else { fail("AXObserverCreate failed") }
    for n in notifications {
        let status = AXObserverAddNotification(observer, app, n as CFString, nil)
        if status != .success { print("register \(n): AXError \(status.rawValue)") }
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

    // Listen-only event tap: counts events, never records key characters.
    var counts = [String: Int]()
    let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
    let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
        callback: { _, type, event, info in
            let box = Unmanaged<NSMutableDictionary>.fromOpaque(info!).takeUnretainedValue()
            let key = "\(type.rawValue)"; box[key] = ((box[key] as? Int) ?? 0) + 1
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(tapCounts).toOpaque())
    print(tap == nil ? "event tap: DENIED (needs Input Monitoring for listenOnly)" : "event tap: created")
    if let tap {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    CFRunLoopRunInMode(.defaultMode, seconds, false)
    print("event counts by CGEventType raw value: \(tapCounts)")
    _ = counts; counts = [:]
}
let tapCounts = NSMutableDictionary()

// MARK: main
let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "preflight":
    print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
    print("CGPreflightListenEventAccess (Input Monitoring): \(CGPreflightListenEventAccess())")
    print("CGPreflightPostEventAccess: \(CGPreflightPostEventAccess())")
    print("CGPreflightScreenCaptureAccess: \(CGPreflightScreenCaptureAccess())")
case "dump" where args.count > 2:
    requireTrust(); dump(appElement(pid_t(args[2]) ?? 0), depth: 0)
case "observe" where args.count > 3:
    observe(pid_t(args[2]) ?? 0, seconds: Double(args[3]) ?? 10)
case "replay" where args.count > 3:
    replay(pid_t(args[2]) ?? 0, args[3])
default:
    fail("usage: harness preflight | dump <pid> | observe <pid> <seconds> | replay <pid> <steps.json>")
}
