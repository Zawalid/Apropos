import Foundation
import Testing

@testable import Apropos

struct DataFootprintTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func sizesFilesAndFoldersAndIgnoresMissingOnes() throws {
        let root = try scratch()
        let file = root.appendingPathComponent("a.json")
        try Data(repeating: 1, count: 100).write(to: file)
        let folder = root.appendingPathComponent("commands")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 50).write(to: folder.appendingPathComponent("c.json"))
        let footprint = DataFootprint.of([file, folder, root.appendingPathComponent("missing")])
        #expect(footprint.exists && footprint.bytes == 150 && footprint.modified != nil)
        #expect(!DataFootprint.of([root.appendingPathComponent("missing")]).exists)
    }

    @Test func exportCopiesWhatExists() throws {
        let root = try scratch()
        let file = root.appendingPathComponent("usage.json")
        try Data("x".utf8).write(to: file)
        let destination = root.appendingPathComponent("out")
        let copied = try DataExport.copy([file, root.appendingPathComponent("nothing.json")], into: destination)
        #expect(copied == ["usage.json"])
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("usage.json").path))
    }
}
