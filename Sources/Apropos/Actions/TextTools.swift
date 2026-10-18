import Foundation

public enum TextToolError: Error, Equatable, Sendable {
    /// The input is not valid for the transformation (bad base64, bad JSON, bad percent-encoding).
    case invalidInput
}

/// Pure text transformations behind the built-in text actions. No I/O, no state, easy to test.
public enum TextTools {
    // MARK: Case

    /// Words of an identifier or sentence: split on anything that is not a letter or digit and on camelCase
    /// boundaries (`fooBar` is foo, bar; `HTTPServer` is http, server).
    public static func words(in text: String) -> [String] {
        var words: [String] = []
        var current: [Character] = []
        func flush() {
            if !current.isEmpty { words.append(String(current)) }
            current = []
        }
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                flush()
                continue
            }
            if character.isUppercase, let last = current.last {
                let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
                if last.isLowercase || last.isNumber || (last.isUppercase && nextIsLower) { flush() }
            }
            current.append(character)
        }
        flush()
        return words
    }

    public static func titleCase(_ text: String) -> String { text.capitalized }

    public static func camelCase(_ text: String) -> String {
        words(in: text).enumerated().map { index, word in
            index == 0 ? word.lowercased() : word.lowercased().capitalized
        }.joined()
    }

    public static func snakeCase(_ text: String) -> String { words(in: text).map { $0.lowercased() }.joined(separator: "_") }

    public static func kebabCase(_ text: String) -> String { words(in: text).map { $0.lowercased() }.joined(separator: "-") }

    // MARK: Lines

    public static func lines(_ text: String) -> [String] {
        var parts = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    public static func sortLines(_ text: String) -> String {
        lines(text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
    }

    /// Keeps the first of each repeated line, in order.
    public static func uniqueLines(_ text: String) -> String {
        var seen = Set<String>()
        return lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    /// One line: each line trimmed, empty ones dropped, joined with a space.
    public static func joinLines(_ text: String) -> String {
        lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Counting and wrapping

    public static func counts(_ text: String) -> String {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lineCount = lines(text).count
        func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        return "\(plural(wordCount, "word")), \(plural(text.count, "character")), \(plural(lineCount, "line"))"
    }

    public static func quote(_ text: String) -> String { "\u{201C}\(trim(text))\u{201D}" }

    public static func codeBlock(_ text: String) -> String { "```\n\(text.trimmingCharacters(in: .newlines))\n```" }

    public static func markdownQuote(_ text: String) -> String {
        lines(trim(text)).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }

    // MARK: Encoding

    public static func urlEncode(_ text: String) -> String { text.percentEncodedForURL }

    public static func urlDecode(_ text: String) throws -> String {
        guard let decoded = text.removingPercentEncoding else { throw TextToolError.invalidInput }
        return decoded
    }

    public static func base64Encode(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    public static func base64Decode(_ text: String) throws -> String {
        var compact = text.filter { !$0.isWhitespace }
        compact = compact.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let missing = (4 - compact.count % 4) % 4
        compact += String(repeating: "=", count: missing)
        guard let data = Data(base64Encoded: compact), let decoded = String(data: data, encoding: .utf8) else {
            throw TextToolError.invalidInput
        }
        return decoded
    }

    // MARK: JSON

    private static func jsonObject(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { throw TextToolError.invalidInput }
        return object
    }

    public static func jsonPretty(_ text: String) throws -> String {
        try jsonString(jsonObject(text), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    public static func jsonMinify(_ text: String) throws -> String {
        try jsonString(jsonObject(text), options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    private static func jsonString(_ object: Any, options: JSONSerialization.WritingOptions) throws -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            throw TextToolError.invalidInput
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Objects and arrays only: a bare number or word is not worth offering JSON actions for.
    public static func isJSON(_ text: String) -> Bool {
        let trimmed = trim(text)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return (try? jsonObject(trimmed)) != nil
    }

    // MARK: Links

    /// The http(s) URL a selection is, if it is exactly one. A bare `www.` address gets https.
    public static func webURL(from text: String) -> URL? {
        let trimmed = trim(text)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let candidate = trimmed.lowercased().hasPrefix("www.") ? "https://" + trimmed : trimmed
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, host.contains(".") || host == "localhost"
        else { return nil }
        return url
    }

    // MARK: Git remotes

    /// The https address of a repository's web page from a remote URL: `git@github.com:me/repo.git`,
    /// `ssh://git@host/me/repo` and `https://host/me/repo.git` all give `https://host/me/repo`. Credentials in the
    /// URL are dropped. Nil for anything that is not a recognizable remote.
    public static func repositoryWebURL(fromRemote remote: String) -> URL? {
        var text = trim(remote)
        guard !text.isEmpty else { return nil }
        var host: String
        var path: String
        if let range = text.range(of: "://") {
            let scheme = text[..<range.lowerBound].lowercased()
            guard ["http", "https", "ssh", "git"].contains(scheme) else { return nil }
            var rest = String(text[range.upperBound...])
            if let at = rest.firstIndex(of: "@"), at < (rest.firstIndex(of: "/") ?? rest.endIndex) {
                rest = String(rest[rest.index(after: at)...])
            }
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            host = String(rest[..<slash])
            path = String(rest[rest.index(after: slash)...])
            if let colon = host.firstIndex(of: ":"), scheme == "ssh" || scheme == "git" { host = String(host[..<colon]) }
        } else {
            // scp-like: user@host:path
            guard let colon = text.firstIndex(of: ":"), !text.hasPrefix("/") else { return nil }
            var hostPart = String(text[..<colon])
            if let at = hostPart.firstIndex(of: "@") { hostPart = String(hostPart[hostPart.index(after: at)...]) }
            host = hostPart
            path = String(text[text.index(after: colon)...])
            text = ""
        }
        if path.hasSuffix(".git") { path.removeLast(4) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty, !path.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" })
        else { return nil }
        return URL(string: "https://\(host)/\(path)")
    }
}
