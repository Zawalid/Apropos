import Foundation
import Testing

@testable import Apropos

struct ChangelogTests {
    private let sample = """
        # Changelog

        Intro text.

        ## [Unreleased]

        ### Added
        - Sequences: chain steps
          into one command.
        - Send to.

        ### Fixed
        - A crash.

        ## [0.1.0] - 2026-10-01

        ### Added
        - First thing.
        """

    @Test func parsesReleasesSectionsAndWrappedItems() {
        let releases = ChangelogParser.parse(sample)
        #expect(releases.map(\.version) == ["Unreleased", "0.1.0"])
        #expect(releases[0].isUnreleased && releases[1].date == "2026-10-01")
        #expect(releases[0].sections.map(\.title) == ["Added", "Fixed"])
        #expect(releases[0].sections[0].items == ["Sequences: chain steps into one command.", "Send to."])
    }

    @Test func theRealChangelogParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let releases = ChangelogParser.parse(text)
        #expect(releases.first?.isUnreleased == true)
        #expect(releases.first?.sections.isEmpty == false)
    }

    @Test func supportReportHasNoPersonalContent() {
        let report = SupportReport(
            version: "0.1.0", build: "1", macOS: "26.0", accessibility: true, inputMonitoring: false,
            contextSensing: true, shortcutRegistered: true, settingsSaved: true, commands: 3, destinations: 7,
            learnedRuns: 120)
        #expect(report.text.contains("Apropos 0.1.0 (1)") && report.text.contains("Learned runs: 120"))
        #expect(!report.text.contains("/Users"))
    }
}
