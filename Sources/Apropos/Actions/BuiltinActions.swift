import CryptoKit
import Foundation

/// The Swift functions behind the built-in catalogue (`Resources/ActionPacks/builtin.json`). Each takes the context and
/// returns the text to deliver, or nil when its effect was the point.
enum BuiltinActions {
    static let functions: ActionFunctionRegistry = {
        var table: [String: ActionFunction] = [:]

        func textFunction(_ name: String, _ transform: @escaping @Sendable (String) throws -> String) {
            table[name] = { input, _ in
                guard let text = input.scalar(.text) else { throw ActionError.missingContext(.selectedText) }
                return try transform(text)
            }
        }
        textFunction("text.upper") { $0.uppercased() }
        textFunction("text.lower") { $0.lowercased() }
        textFunction("text.title", TextTools.titleCase)
        textFunction("text.camel", TextTools.camelCase)
        textFunction("text.snake", TextTools.snakeCase)
        textFunction("text.kebab", TextTools.kebabCase)
        textFunction("text.trim", TextTools.trim)
        textFunction("text.sortLines", TextTools.sortLines)
        textFunction("text.uniqueLines", TextTools.uniqueLines)
        textFunction("text.joinLines", TextTools.joinLines)
        textFunction("text.count", TextTools.counts)
        textFunction("text.quote", TextTools.quote)
        textFunction("text.codeBlock", TextTools.codeBlock)
        textFunction("text.markdownQuote", TextTools.markdownQuote)
        textFunction("text.urlEncode", TextTools.urlEncode)
        textFunction("text.urlDecode", TextTools.urlDecode)
        textFunction("text.base64Encode", TextTools.base64Encode)
        textFunction("text.base64Decode", TextTools.base64Decode)
        textFunction("text.jsonPretty", TextTools.jsonPretty)
        textFunction("text.jsonMinify", TextTools.jsonMinify)

        table["text.openLink"] = { input, services in
            guard let text = input.scalar(.text), let url = TextTools.webURL(from: text) else { throw ActionError.invalidInput }
            guard await services.openURL(url) else { throw ActionError.unavailable("The link could not be opened.") }
            return nil
        }

        table["files.paths"] = { input, _ in
            guard let paths = input.list(.files) else { throw ActionError.missingContext(.selectedFiles) }
            return paths.joined(separator: "\n")
        }
        table["files.names"] = { input, _ in
            guard let names = input.list(.fileNames) else { throw ActionError.missingContext(.selectedFiles) }
            return names.joined(separator: "\n")
        }
        table["files.sha256"] = { input, _ in
            let files = input.values.selectedFiles
            guard !files.isEmpty else { throw ActionError.missingContext(.selectedFiles) }
            var lines: [String] = []
            for file in files {
                let hash = try sha256(of: file)
                lines.append(files.count == 1 ? hash : "\(hash)  \(file.lastPathComponent)")
            }
            return lines.joined(separator: "\n")
        }
        table["files.zip"] = { input, services in try await zip(input.values.selectedFiles, services: services) }

        table["page.url"] = { input, _ in
            guard let url = input.scalar(.url) else { throw ActionError.missingContext(.pageURL) }
            return url
        }
        table["page.title"] = { input, _ in
            guard let title = input.scalar(.title) else { throw ActionError.unavailable("This page has no title.") }
            return title
        }
        table["page.markdownLink"] = { input, _ in
            guard let url = input.scalar(.url) else { throw ActionError.missingContext(.pageURL) }
            let title = input.scalar(.title) ?? input.values.pageURL?.host ?? url
            return "[\(markdownEscaped(title))](\(url))"
        }

        table["git.branch"] = { input, _ in
            guard let branch = input.scalar(.branch) else { throw ActionError.unavailable("No branch is checked out.") }
            return branch
        }
        table["git.openRemote"] = { input, services in
            guard let repo = input.scalar(.repo) else { throw ActionError.missingContext(.gitRepo) }
            guard let remote = try await remoteURL(repo: repo, services: services),
                let web = TextTools.repositoryWebURL(fromRemote: remote)
            else { throw ActionError.unavailable("This repository has no web remote.") }
            guard await services.openURL(web) else { throw ActionError.unavailable("The link could not be opened.") }
            return nil
        }
        return ActionFunctionRegistry(table)
    }()

    static func markdownEscaped(_ title: String) -> String {
        title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func sha256(of file: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            throw ActionError.unavailable("A selected file could not be read.")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Zips the selected files next to the first one. The archive is named after a single file, or `Archive.zip`, and
    /// never replaces an existing file.
    static func zip(_ files: [URL], services: ActionServices) async throws -> String {
        guard let first = files.first else { throw ActionError.missingContext(.selectedFiles) }
        let parent = first.deletingLastPathComponent()
        guard files.allSatisfy({ $0.deletingLastPathComponent() == parent }) else {
            throw ActionError.unavailable("Select files from one folder to compress them.")
        }
        let base = files.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        var destination = parent.appendingPathComponent("\(base).zip")
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            counter += 1
            destination = parent.appendingPathComponent("\(base) \(counter).zip")
        }
        let request = ProcessRequest(
            executable: "/usr/bin/zip",
            arguments: ["-r", "-q", destination.path, "--"] + files.map(\.lastPathComponent),
            workingDirectory: parent.path, timeout: 110)
        let output = try await services.process(request)
        guard output.status == 0 else { throw ActionError.backendFailed(status: output.status) }
        return "Created \(destination.lastPathComponent)"
    }

    /// The URL of `origin`, else of the first remote.
    static func remoteURL(repo: String, services: ActionServices) async throws -> String? {
        func git(_ arguments: [String]) async throws -> String? {
            let output = try await services.process(
                ProcessRequest(executable: "/usr/bin/git", arguments: ["--no-optional-locks", "-C", repo] + arguments, timeout: 5))
            guard output.status == 0 else { return nil }
            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let origin = try await git(["config", "--get", "remote.origin.url"]) { return origin }
        guard let first = try await git(["remote"])?.split(separator: "\n").first else { return nil }
        return try await git(["config", "--get", "remote.\(first).url"])
    }
}
