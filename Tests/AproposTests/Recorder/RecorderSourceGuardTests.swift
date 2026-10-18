import Foundation
import Testing

/// Reads the recorder's own source files to keep two promises that are easy to break by accident: only one file can
/// create an event tap, and no file can ask an event for the characters it carries.
@Suite("Recorder source guards")
struct RecorderSourceGuardTests {
    private var recorderDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Apropos/Recorder")
    }

    private func sources() throws -> [(name: String, text: String)] {
        let enumerator = FileManager.default.enumerator(at: recorderDirectory, includingPropertiesForKeys: nil)
        var found: [(String, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    @Test func onlyTheLiveSourceCreatesAnEventTap() throws {
        let files = try sources()
        #expect(files.count > 8)
        let creators = files.filter { $0.text.contains("tapCreate") }.map(\.name)
        #expect(creators == ["LiveCaptureSource.swift"])
    }

    @Test func noFileReadsTheCharactersOfAnEvent() throws {
        let forbidden = [
            "keyboardGetUnicodeString", "charactersIgnoringModifiers", "NSEvent", "addGlobalMonitor",
            "addLocalMonitor", "CGEventKeyboardGetUnicodeString", "pasteboard", "NSPasteboard",
        ]
        for file in try sources() {
            for word in forbidden {
                #expect(!file.text.contains(word), "\(file.name) mentions \(word)")
            }
        }
    }

    @Test func noFileTouchesTheNetworkOrTheScreen() throws {
        let forbidden = ["URLSession", "CGWindowListCreateImage", "ScreenCaptureKit", "CGDisplayCreateImage"]
        for file in try sources() {
            for word in forbidden {
                #expect(!file.text.contains(word), "\(file.name) mentions \(word)")
            }
        }
    }

    @Test func noTestCreatesALiveSource() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let me = URL(fileURLWithPath: #filePath).lastPathComponent
        for url in try FileManager.default.contentsOfDirectory(at: tests, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" && url.lastPathComponent != me {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("LiveCaptureSource()"), "\(url.lastPathComponent) creates a live source")
            #expect(!text.contains("LiveHitTester()"), "\(url.lastPathComponent) creates a live hit tester")
        }
    }
}
