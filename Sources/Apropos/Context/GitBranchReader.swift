import Foundation

/// Finds the git branch of a folder. Injected into the service so tests never spawn git.
public protocol GitBranchLookup: Sendable {
    func branch(forFolder path: String, timeout: TimeInterval) -> String?
    /// The top level of the repository holding the folder, or nil outside one.
    func repoRoot(forFolder path: String, timeout: TimeInterval) -> String?
}

extension GitBranchLookup {
    public func repoRoot(forFolder path: String, timeout: TimeInterval) -> String? { nil }
}

/// Runs a read-only git command with a short timeout. Works for any app: give it any folder or file path.
public struct GitBranchReader: GitBranchLookup {
    public init() {}

    public func branch(forFolder path: String, timeout: TimeInterval = 0.12) -> String? {
        guard let folder = Self.existingFolder(for: path) else { return nil }
        if let name = run(["symbolic-ref", "--short", "-q", "HEAD"], in: folder, timeout: timeout) { return name }
        // Detached HEAD: show the short commit hash.
        return run(["rev-parse", "--short", "HEAD"], in: folder, timeout: timeout)
    }

    public func repoRoot(forFolder path: String, timeout: TimeInterval = 0.12) -> String? {
        guard let folder = Self.existingFolder(for: path) else { return nil }
        return run(["rev-parse", "--show-toplevel"], in: folder, timeout: timeout)
    }

    /// The path itself when it is a folder, else its parent when that is one.
    static func existingFolder(for path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return path
        }
        let parent = (path as NSString).deletingLastPathComponent
        isDirectory = false
        if FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue {
            return parent
        }
        return nil
    }

    private func run(_ arguments: [String], in folder: String, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // --no-optional-locks keeps this strictly read-only: git will not refresh the index.
        process.arguments = ["--no-optional-locks", "-C", folder] + arguments
        process.environment = ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return ContextText.clean(String(decoding: data, as: UTF8.self))
    }
}
