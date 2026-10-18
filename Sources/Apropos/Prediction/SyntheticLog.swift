import Foundation

/// A deterministic random source (SplitMix64), so generated logs and evaluations repeat exactly.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }
    mutating func pick<T>(_ options: [T]) -> T { options[Int.random(in: 0..<options.count, using: &self)] }
}

/// What the synthetic person is like.
public struct SyntheticProfile: Sendable {
    public var seed: UInt64 = 1
    public var days = 180
    /// Chance of an unrelated command appearing between two steps.
    public var noise = 0.06
    /// Chance of a step of another task appearing between two steps of a routine.
    public var interleave = 0.12
    /// The day (counted from the start) when the habits change: tests are followed by an archive instead of a commit.
    public var driftDay: Int?
    public var start = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01 00:00 UTC
    public var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    public init() {}
}

/// Makes a run log that behaves like a person with routines: a development loop across Xcode and Terminal, a writing
/// task in the morning, mail at the edges of the day, browsing in the evening, tasks that interleave, random
/// commands, and a habit that changes part way. Only for tests, the evaluation harness and documentation numbers: it
/// shows the model can find structure that is there, not that real people have it.
public enum SyntheticLog {
    private struct Step {
        let app: String
        let menu: String
        /// The command and how likely it is at this step.
        let options: [(title: String, weight: Double)]
        let kinds: [ContextKind]
        let skipChance: Double
    }

    private struct Routine {
        let name: String
        let steps: [Step]
    }

    private static let xcode = "com.apple.dt.Xcode"
    private static let terminal = "com.apple.Terminal"
    private static let safari = "com.apple.Safari"
    private static let notes = "com.apple.Notes"
    private static let mail = "com.apple.mail"

    private static func routines(drifted: Bool) -> [String: Routine] {
        let afterTests = drifted ? "Archive" : "Git Commit"
        return [
            "dev": Routine(
                name: "dev",
                steps: [
                    Step(
                        app: xcode, menu: "Product", options: [("Build", 1)], kinds: [.branch, .document], skipChance: 0
                    ),
                    Step(
                        app: xcode, menu: "Product", options: [("Run Tests", 0.85), ("Run", 0.15)],
                        kinds: [.branch, .document], skipChance: 0),
                    Step(
                        app: terminal, menu: "Git", options: [(afterTests, 0.8), ("Git Diff", 0.2)], kinds: [.branch],
                        skipChance: 0),
                    Step(app: terminal, menu: "Git", options: [("Git Push", 1)], kinds: [.branch], skipChance: 0.3),
                ]),
            "writing": Routine(
                name: "writing",
                steps: [
                    Step(app: notes, menu: "File", options: [("New Note", 1)], kinds: [.document], skipChance: 0),
                    Step(
                        app: notes, menu: "Format", options: [("Bold", 0.5), ("Heading", 0.5)],
                        kinds: [.document, .selection], skipChance: 0.1),
                    Step(app: notes, menu: "File", options: [("Share", 1)], kinds: [.document], skipChance: 0.5),
                ]),
            "mail": Routine(
                name: "mail",
                steps: [
                    Step(app: mail, menu: "Mailbox", options: [("Get New Mail", 1)], kinds: [], skipChance: 0),
                    Step(
                        app: mail, menu: "Message", options: [("Reply", 0.6), ("Archive Message", 0.4)],
                        kinds: [.selection],
                        skipChance: 0),
                    Step(app: mail, menu: "Message", options: [("Send", 1)], kinds: [], skipChance: 0.4),
                ]),
            "browse": Routine(
                name: "browse",
                steps: [
                    Step(app: safari, menu: "File", options: [("New Tab", 1)], kinds: [.url], skipChance: 0),
                    Step(
                        app: safari, menu: "View", options: [("Reload Page", 0.6), ("Bookmark This Page", 0.4)],
                        kinds: [.url], skipChance: 0.2),
                ]),
        ]
    }

    private static let noisePool: [(String, String, String)] = (0..<40).map { index in
        let apps = [xcode, terminal, safari, notes, mail]
        return (apps[index % apps.count], "Misc", "Misc Command \(index)")
    }

    private struct Raw {
        let time: Double
        let app: String
        let menu: String
        let title: String
        let kinds: [ContextKind]
    }

    /// The events of `profile.days` days, oldest first.
    public static func generate(_ profile: SyntheticProfile = SyntheticProfile()) -> [RunEvent] {
        var random = SeededGenerator(seed: profile.seed)
        var raws: [Raw] = []
        let before = routines(drifted: false)
        let after = routines(drifted: true)
        let allNames = ["dev", "writing", "mail", "browse"]

        func play(_ name: String, at start: Double, day: Int) {
            let set = (profile.driftDay.map { day >= $0 } ?? false) ? after : before
            guard let routine = set[name] else { return }
            var time = start
            for step in routine.steps {
                if profile.interleave > 0, random.chance(profile.interleave) {
                    let otherName = random.pick(allNames.filter { $0 != name })
                    if let other = set[otherName], let otherStep = other.steps.randomElement(using: &random) {
                        time += Double.random(in: 4...20, using: &random)
                        raws.append(raw(otherStep, time, &random))
                    }
                }
                if profile.noise > 0, random.chance(profile.noise) {
                    let item = random.pick(noisePool)
                    time += Double.random(in: 4...20, using: &random)
                    raws.append(Raw(time: time, app: item.0, menu: item.1, title: item.2, kinds: []))
                }
                if step.skipChance > 0, random.chance(step.skipChance) { continue }
                time += Double.random(in: 5...45, using: &random)
                raws.append(raw(step, time, &random))
            }
        }

        for day in 0..<profile.days {
            let midnight = profile.start.addingTimeInterval(Double(day) * 86_400).timeIntervalSince1970
            let weekday = profile.calendar.component(.weekday, from: Date(timeIntervalSince1970: midnight))
            let weekend = weekday == 1 || weekday == 7
            func hour(_ from: Double, _ to: Double) -> Double {
                midnight + Double.random(in: from...to, using: &random) * 3_600
            }
            if weekend {
                for _ in 0..<Int.random(in: 3...6, using: &random) { play("browse", at: hour(10, 22), day: day) }
                if random.chance(0.5) { play("writing", at: hour(10, 12), day: day) }
            } else {
                for _ in 0..<Int.random(in: 1...2, using: &random) { play("mail", at: hour(8, 9.5), day: day) }
                for _ in 0..<Int.random(in: 1...2, using: &random) { play("writing", at: hour(9, 11), day: day) }
                for _ in 0..<Int.random(in: 4...8, using: &random) { play("dev", at: hour(11, 18), day: day) }
                if random.chance(0.7) { play("mail", at: hour(17, 19), day: day) }
                for _ in 0..<Int.random(in: 1...3, using: &random) { play("browse", at: hour(19, 23), day: day) }
            }
        }
        return events(from: raws)
    }

    private static func raw(_ step: Step, _ time: Double, _ random: inout SeededGenerator) -> Raw {
        let total = step.options.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total, using: &random)
        var title = step.options[0].title
        for option in step.options {
            if roll < option.weight {
                title = option.title
                break
            }
            roll -= option.weight
        }
        return Raw(time: time, app: step.app, menu: step.menu, title: title, kinds: step.kinds)
    }

    private static func events(from raws: [Raw]) -> [RunEvent] {
        var events: [RunEvent] = []
        events.reserveCapacity(raws.count)
        let ordered = raws.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(
            \.element)
        var last: RunEvent?
        for item in ordered {
            let id = CommandID.base(bundleID: item.app, path: [item.menu], title: item.title)
            let time = max(item.time.rounded(.down), last?.time ?? 0)
            let previous = last.flatMap { time - $0.time <= SequenceLog.sessionWindow ? $0.command : nil }
            guard
                let event = RunEvent(
                    kind: .run, time: time, command: id, app: item.app, previous: previous,
                    kindNames: item.kinds.map(\.rawValue), offered: nil)
            else { continue }
            events.append(event)
            last = event
        }
        return events
    }
}
