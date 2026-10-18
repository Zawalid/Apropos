#if DEBUG
    import AppKit
    import SwiftUI

    // Renders every scene of `PreviewCatalog` to build/previews/<id>-<dark|light>.png without opening the app: a separate
    // command line process, so it never touches the copy you run. The windows are fully transparent and never take focus.
    //
    //   scripts/render-previews.sh [output-dir] [scene-id ...]

    MainActor.assumeIsolated {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let output = URL(fileURLWithPath: arguments.first ?? "build/previews", isDirectory: true)
        let wanted = Set(arguments.dropFirst())
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        func settle(_ seconds: TimeInterval) {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        }

        /// A flat stand-in for the desktop, as the agent screenshots use, so light text on glass stays readable.
        func standIn(_ scheme: ColorScheme) -> NSColor {
            scheme == .dark
                ? NSColor(srgbRed: 0.105, green: 0.115, blue: 0.11, alpha: 1)
                : NSColor(srgbRed: 0.93, green: 0.945, blue: 0.94, alpha: 1)
        }

        func flatten(_ rep: NSBitmapImageRep, onto backdrop: NSColor?) -> Data? {
            guard let backdrop else { return rep.representation(using: .png, properties: [:]) }
            guard let image = rep.cgImage,
                let context = CGContext(
                    data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return rep.representation(using: .png, properties: [:]) }
            let bounds = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            context.setFillColor(backdrop.cgColor)
            context.fill(bounds)
            context.draw(image, in: bounds)
            guard let flat = context.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])
        }

        var failures = 0
        for scene in PreviewCatalog.all where wanted.isEmpty || wanted.contains(scene.id) {
            for (scheme, name) in [(ColorScheme.dark, "dark"), (ColorScheme.light, "light")] {
                let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let hosting = NSHostingView(rootView: scene.cell(scheme, drawsBackdrop: false))
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: scene.size), styleMask: [.borderless], backing: .buffered,
                    defer: false)
                // Both, because the glass reads the application's appearance rather than the window's.
                NSApp.appearance = appearance
                window.appearance = appearance
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = hosting
                // Liquid Glass only resolves its dark look in a window the system considers on screen. Fully transparent
                // and mouse-transparent, so nothing is ever visible or in the way.
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                window.orderFrontRegardless()
                hosting.frame = NSRect(origin: .zero, size: scene.size)
                settle(0.6)
                hosting.layoutSubtreeIfNeeded()
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                    print("failed \(scene.id)-\(name): no bitmap")
                    failures += 1
                    continue
                }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                guard let png = flatten(rep, onto: scene.backdrop ? standIn(scheme) : nil) else {
                    print("failed \(scene.id)-\(name): no png")
                    failures += 1
                    continue
                }
                do {
                    try png.write(to: output.appendingPathComponent("\(scene.id)-\(name).png"))
                    print("\(scene.id)-\(name)")
                } catch {
                    print("failed \(scene.id)-\(name): \(error)")
                    failures += 1
                }
            }
        }
        exit(failures == 0 ? 0 : 1)
    }
#else
    print("The preview renderer is only built in Debug.")
#endif
