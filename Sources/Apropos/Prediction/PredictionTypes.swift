import Foundation

/// A coarse part of the day. Four buckets are enough to tell a morning routine from an evening one and keep the counts
/// from being spread thin.
public enum TimeBucket: Int, Sendable, CaseIterable {
    case night, morning, afternoon, evening

    public init(hour: Int) {
        switch hour {
        case 6..<12: self = .morning
        case 12..<18: self = .afternoon
        case 18..<24: self = .evening
        default: self = .night
        }
    }

    var phrase: String {
        switch self {
        case .night: "at night"
        case .morning: "in the morning"
        case .afternoon: "in the afternoon"
        case .evening: "in the evening"
        }
    }
}

public enum DayKind: Int, Sendable {
    case weekday, weekend

    var phrase: String { self == .weekday ? "on weekdays" : "on weekends" }
}

/// Where in the week and the day a moment falls, in the person's calendar.
struct TimeSlot: Hashable, Sendable {
    let bucket: TimeBucket
    let day: DayKind

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .weekday], from: date)
        bucket = TimeBucket(hour: parts.hour ?? 0)
        let weekday = parts.weekday ?? 2
        day = (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }

    var packed: Int32 { Int32(bucket.rawValue * 2 + day.rawValue) }

    var phrase: String { "\(day.phrase) \(bucket.phrase)" }
}

/// Everything the model looks at to predict the next command. No values, only identities and kinds.
public struct PredictionContext: Sendable, Equatable {
    /// Bundle identifier of the frontmost app.
    public var app: String
    /// The commands run just before, most recent first, at most two, each inside the session window of the next.
    public var recent: [CommandID]
    public var date: Date
    /// Kinds of context present, as `ContextKind` raw values.
    public var contextKinds: [String]

    public init(app: String, recent: [CommandID] = [], date: Date, contextKinds: [String] = []) {
        self.app = app
        self.recent = Array(recent.prefix(2))
        self.date = date
        self.contextKinds = PredictionPrivacy.cleanKinds(contextKinds)
    }
}

/// Which evidence a prediction rests mostly on, from the most specific to the least.
public enum PredictionBasis: String, Sendable, Equatable {
    case afterTwoCommands
    case afterCommand
    case afterCommandAnyApp
    case contextKinds
    case timeOfDay
    case appHabit
    case frecency
}

/// One predicted command with how sure the model is and why.
public struct Prediction: Sendable, Equatable {
    public let command: CommandID
    /// The probability, between 0 and 1, that this is the command about to run, after the person's feedback.
    public let confidence: Double
    /// A sentence built from real counts, for example "After Run Tests you chose Commit 9 of 12 times".
    public let reason: String
    public let basis: PredictionBasis

    public init(command: CommandID, confidence: Double, reason: String, basis: PredictionBasis) {
        self.command = command
        self.confidence = confidence
        self.reason = reason
        self.basis = basis
    }

    func withoutReason() -> Prediction {
        Prediction(command: command, confidence: confidence, reason: "", basis: basis)
    }
}

extension CommandID {
    /// A readable title taken from the identity, for sentences about commands that are not on screen: the last menu
    /// item, with the first letter of each word capitalised. A command that is on screen should use its own title.
    public var fallbackTitle: String {
        var text = rawValue
        if let bar = text.firstIndex(of: "|") {
            text = String(text[text.index(after: bar)...])
            if let second = text.firstIndex(of: "|") { text = String(text[..<second]) }
        } else {
            if let colon = text.firstIndex(of: ":") { text = String(text[text.index(after: colon)...]) }
            text = text.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "-", with: " ")
        }
        if let hash = text.lastIndex(of: "#"), text[text.index(after: hash)...].allSatisfy(\.isNumber) {
            text = String(text[..<hash])
        }
        let last = text.split(separator: ">").last.map(String.init) ?? text
        return last.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
