import Foundation

/// How much of the disk something Apropos keeps takes, for the privacy page: counts and sizes, never contents.
public struct DataFootprint: Equatable, Sendable {
    public var bytes = 0
    public var modified: Date?
    public var exists = false

    public init() {}

    /// The total size and the newest change across files and folders. Missing paths count for nothing.
    public static func of(_ urls: [URL]) -> DataFootprint {
        var result = DataFootprint()
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            result.exists = true
            if isDirectory.boolValue {
                let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
                for case let file as URL in walker ?? FileManager.DirectoryEnumerator() {
                    let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                    guard values?.isDirectory != true else { continue }
                    result.bytes += values?.fileSize ?? 0
                    result.merge(values?.contentModificationDate)
                }
            } else {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                result.bytes += values?.fileSize ?? 0
                result.merge(values?.contentModificationDate)
            }
        }
        return result
    }

    private mutating func merge(_ date: Date?) {
        guard let date else { return }
        if let modified, modified >= date { return }
        modified = date
    }
}

/// Copies what Apropos keeps into a folder, so a person can read all of it.
public enum DataExport {
    /// Copies each existing file or folder into `folder` under its own name. Returns the names copied.
    @discardableResult
    public static func copy(_ urls: [URL], into folder: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied: [String] = []
        for url in urls where fm.fileExists(atPath: url.path) {
            let target = folder.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: url, to: target)
            copied.append(url.lastPathComponent)
        }
        return copied
    }
}
