import Foundation

/// One release of the changelog: a version or "Unreleased", an optional date, and its sections (Added, Changed, Fixed).
public struct ChangelogRelease: Identifiable, Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let items: [String]
    }

    public let version: String
    public let date: String?
    public let sections: [Section]

    public var id: String { version }
    public var isUnreleased: Bool { version.lowercased() == "unreleased" }
}

/// Reads a Keep a Changelog file: `## [version] - date` headings, `### Section` headings, `- item` bullets that may
/// continue on indented lines.
public enum ChangelogParser {
    public static func parse(_ text: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var version: String?
        var date: String?
        var sections: [ChangelogRelease.Section] = []
        var sectionTitle: String?
        var items: [String] = []

        func closeSection() {
            if let title = sectionTitle, !items.isEmpty { sections.append(.init(title: title, items: items)) }
            sectionTitle = nil
            items = []
        }
        func closeRelease() {
            closeSection()
            if let version { releases.append(ChangelogRelease(version: version, date: date, sections: sections)) }
            version = nil
            date = nil
            sections = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .newlines)
            if line.hasPrefix("## ") {
                closeRelease()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let open = heading.firstIndex(of: "["), let close = heading.firstIndex(of: "]"), open < close {
                    version = String(heading[heading.index(after: open)..<close])
                    let rest = heading[heading.index(after: close)...].trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                    date = rest.isEmpty ? nil : rest
                } else {
                    version = heading
                }
            } else if line.hasPrefix("### ") {
                closeSection()
                sectionTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- "), sectionTitle != nil {
                items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("  "), !items.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                items[items.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            }
        }
        closeRelease()
        return releases
    }
}

/// What to paste into a bug report. Versions, permission states and counts only: no paths, names or content.
public struct SupportReport: Sendable {
    public var version: String
    public var build: String
    public var macOS: String
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var contextSensing: Bool
    public var shortcutRegistered: Bool
    public var settingsSaved: Bool
    public var commands: Int
    public var destinations: Int
    public var learnedRuns: Int

    public init(
        version: String, build: String, macOS: String, accessibility: Bool, inputMonitoring: Bool,
        contextSensing: Bool, shortcutRegistered: Bool, settingsSaved: Bool, commands: Int, destinations: Int,
        learnedRuns: Int
    ) {
        self.version = version
        self.build = build
        self.macOS = macOS
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.contextSensing = contextSensing
        self.shortcutRegistered = shortcutRegistered
        self.settingsSaved = settingsSaved
        self.commands = commands
        self.destinations = destinations
        self.learnedRuns = learnedRuns
    }

    public var text: String {
        func word(_ on: Bool) -> String { on ? "yes" : "no" }
        return """
            Apropos \(version) (\(build))
            macOS \(macOS)
            Accessibility: \(word(accessibility))
            Input Monitoring: \(word(inputMonitoring))
            Context sensing: \(word(contextSensing))
            Shortcut registered: \(word(shortcutRegistered))
            Settings saved: \(word(settingsSaved))
            Your commands: \(commands)
            Destinations: \(destinations)
            Learned runs: \(learnedRuns)
            """
    }
}
