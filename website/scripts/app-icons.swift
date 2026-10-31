// Saves the icon macOS shows for each app, as a 256 px PNG, into src/assets/apps/<slug>.png.
//   swift scripts/app-icons.swift "/Applications/Safari.app" "/System/Applications/Notes.app" ...
// Reads only the icon, launches nothing.
import AppKit

// Run from the website folder.
let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("src/assets/apps")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for path in CommandLine.arguments.dropFirst() {
    guard FileManager.default.fileExists(atPath: path) else {
        print("missing \(path)")
        continue
    }
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
    let icon = NSWorkspace.shared.icon(forFile: path)
    let side = 256
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: out.appendingPathComponent("\(slug).png"))
    print("\(slug).png")
}
