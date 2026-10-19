import Foundation

/// Every number the ranking depends on, in one place, so the evaluation can compare settings and the app can use the best
/// ones. `legacy` is how ranking worked before the learning work, kept to measure against.
public struct RankingTuning: Sendable, Equatable {
    /// Added when the whole title was typed, when its start was, when a word's start was, when the first letters of its
    /// words were. A person who types the start of a name means that name.
    public var exactBonus = 80
    public var prefixBonus = 34
    public var wordPrefixBonus = 14
    public var initialsBonus = 24
    /// Points taken off per extra character in a title that was matched at its start, up to `lengthPenaltyCap`: typing
    /// "clo" means Close before Close Other Tabs.
    public var lengthPenalty = 0.6
    public var lengthPenaltyCap = 20.0
    /// Finds "foledr" for "folder": one swap of neighbouring letters.
    public var typoTolerance = true
    public var typoPenalty = 26
    /// The most the learned use of a command can add, and how fast use fades. `halfLifeDays` nil keeps the old frecency.
    public var usageCap = 60.0
    public var halfLifeDays: Double? = 21
    /// How many effective uses give half of `usageCap`.
    public var usageHalfPoint = 4.0
    /// Scale use by how good the text match is, so use lifts a good match and does not rescue a poor one.
    public var gateUsage = true
    /// The most a learned shorthand can add: what the person types for this command, learned from what they chose.
    public var learnedMax = 150.0
    /// A learned name counts only once it has been chosen this many times, and this large a share of the time.
    public var learnedMinSupport = 3.0
    public var learnedMinShare = 0.6
    /// The most what usually comes next (after the last command, at this time, in this context) can add to a match.
    public var priorMax = 45.0
    /// A small lift for actions on what is selected, which exist only when they apply.
    public var contextBonus = 8

    /// With no query, inside each menu the commands you use come first, and the menus keep their order.
    public var orderMenusByUse = true
    /// How many suggestions head the list as it opens, and how strong a habit must be to qualify.
    public var suggestionLimit = 5
    public var suggestionMinimumHabit = 2.0

    public init() {}

    public static var legacy: RankingTuning {
        var tuning = RankingTuning()
        tuning.exactBonus = 40
        tuning.prefixBonus = 0
        tuning.wordPrefixBonus = 0
        tuning.initialsBonus = 0
        tuning.lengthPenalty = 0
        tuning.typoTolerance = false
        tuning.halfLifeDays = nil
        tuning.gateUsage = false
        tuning.learnedMax = 0
        tuning.contextBonus = 0
        tuning.priorMax = 0
        tuning.orderMenusByUse = false
        tuning.suggestionMinimumHabit = 0
        return tuning
    }
}

/// What the person's past choices say about a query, for one command.
public struct LearnedSignal: Sendable, Equatable {
    /// Of the times this query (or one it starts) led to a choice in this app, the share that chose this command.
    public var share = 0.0
    /// How many such choices there were, so one chance event counts for less than a habit.
    public var support = 0.0
    public static let none = LearnedSignal()
}
