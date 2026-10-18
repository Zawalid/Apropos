import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Send to: learning")
struct SendToLearningTests {
    private func command(_ target: SendTarget) -> Command {
        Command(id: target.commandID.rawValue, title: "x", path: ["Selected text"], source: .sendTo(target))
    }

    @Test func commandIdentitiesAreIdsOnlyAndPerKind() {
        #expect(SendTarget.generic(.text).commandID.rawValue == "send:text")
        #expect(SendTarget.destination("dest:notes", .text).commandID.rawValue == "send:text>dest:notes")
        #expect(SendTarget.destination("dest:notes", .page).commandID.rawValue == "send:page>dest:notes")
        let folder = FolderDestinations.id(for: URL(fileURLWithPath: "/Users/me/Secret Project"), move: false)
        let id = SendTarget.destination(folder, .files).commandID
        // The path never appears: only a short hash of it.
        #expect(!id.rawValue.contains("Secret"))
        #expect(id.bundleID == nil)
        #expect(PredictionPrivacy.isLoggable(id))
    }

    @Test func aSendIsRecordedInTheUsageStoreAsAnIdAndATime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-learn-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url, writeDelay: .zero)
        let sent = command(.destination("dest:notes", .text))
        store.recordRun(of: sent)
        store.recordRun(of: sent)
        #expect(store.runCount(sent.stableID) == 2)
        #expect(store.runCount(command(.destination("dest:notes", .page)).stableID) == 0)
        let file = try String(contentsOf: url, encoding: .utf8)
        #expect(file.contains("send:text>dest:notes"))
        // Nothing but ids and times: no field could hold content.
        #expect(!file.contains("Selected text"))
        #expect(!file.contains("\"title\""))
    }

    @Test func aSendEntersTheRunLogWithKindsOnly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-log-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = SequenceLog(url: url, writeDelay: .zero)
        let sent = command(.destination("dest:mail", .text))
        let event = try #require(
            log.recordRun(sent.stableID, app: "com.apple.Safari", contextKinds: [.selection, .url]))
        let data = try JSONEncoder().encode(event)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("send:text>dest:mail"))
        #expect(json.contains("com.apple.Safari"))
        #expect(!json.contains("Selected text"))
        #expect(SequenceLog.isRecordable(sent))
    }

    @Test func resettingLearnedRankingForgetsTheRecentDestinations() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-reset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url, writeDelay: .zero)
        let sent = command(.destination("dest:notes", .text))
        store.recordRun(of: sent)
        #expect(store.frecency(sent.stableID) > 0)
        store.resetLearnedRanking()
        #expect(store.frecency(sent.stableID) == 0)
    }

    @Test func aPinnedDestinationRowKeepsItsPinThroughTheUsageStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apropos-pin-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageStore(url: url, writeDelay: .zero)
        let row = command(.destination("dest:notes", .text))
        store.setPinned(true, for: row.stableID)
        let signal = store.rankingSignal()
        #expect(signal.pinOrder(for: row) != nil)
    }
}
