import Foundation

/// Limits that keep a resolve from stalling on a huge tree or a hung app.
public struct ResolveBudget: Sendable {
    public var maxNodes: Int
    public var maxDepth: Int
    /// Checked between nodes. Returning true stops the search with `.budgetExceeded`.
    public var isExpired: @Sendable () -> Bool

    public init(maxNodes: Int = 1500, maxDepth: Int = 8, isExpired: @escaping @Sendable () -> Bool = { false }) {
        self.maxNodes = maxNodes
        self.maxDepth = maxDepth
        self.isExpired = isExpired
    }
}

/// What one locator did.
public enum LocatorOutcome: Equatable, Sendable {
    case matched
    case notFound
    /// More than one element matched, so the locator was not used.
    case ambiguous(count: Int)
    /// The locator does not apply to this kind of step.
    case notApplicable
}

public struct LocatorAttempt: Equatable, Sendable {
    public let kind: LocatorKind?
    public let outcome: LocatorOutcome
}

public enum StepResolveFailure: Equatable, Sendable {
    case notFound
    /// Every locator that matched, matched more than one element.
    case ambiguous
    /// The target is a password field.
    case secureField
    /// The app has no menu bar to search, yet.
    case noMenuBar
    /// The tree was too big or too slow to search in the budget.
    case budgetExceeded
}

/// The result of looking for one step's element. Carries the element itself only on success; everything else is
/// plain values safe to log (kinds and counts, never titles).
public struct StepResolution: Sendable {
    public let element: (any AXNode)?
    public let matchedKind: LocatorKind?
    public let isEnabled: Bool
    public let attempts: [LocatorAttempt]
    public let failure: StepResolveFailure?
    /// True when the strongest kind of locator the step has did not match and a weaker one did.
    public let isDegraded: Bool

    public var isMatch: Bool { element != nil }
}

/// Finds a step's element in an Accessibility tree. It only reads, so it is safe to run at any time and in the
/// background, and it never reads the value of a field.
///
/// Locators are tried strongest first (`LocatorKind` order). One that matches exactly one element wins. One that
/// matches several is skipped, never guessed from, and if nothing else matches the step fails as ambiguous.
public struct StepResolver: Sendable {
    public var budget: ResolveBudget

    public init(budget: ResolveBudget = ResolveBudget()) { self.budget = budget }

    /// - Parameter application: The application element of the step's app.
    public func resolve(_ step: UIStep, in application: any AXNode) -> StepResolution {
        resolve(locators: step.locators, scope: step.action == .menu ? .menuBar : .windows, in: application)
    }

    /// Looks for an element described by one locator among the windows. Used for the expectation of a step.
    public func find(_ locator: StepLocator, inWindowsOf application: any AXNode) -> StepResolution {
        resolve(locators: [locator], scope: .windows, in: application)
    }

    enum Scope { case menuBar, windows }

    private func resolve(locators: [StepLocator], scope: Scope, in application: any AXNode) -> StepResolution {
        let ordered = locators.enumerated()
            .compactMap { offset, locator in locator.kind.map { (offset: offset, kind: $0, locator: locator) } }
            .sorted { ($0.kind.rank, $0.offset) < ($1.kind.rank, $1.offset) }

        var attempts: [LocatorAttempt] = []
        var collected: Collected?
        var strongest: LocatorKind?
        for candidate in ordered {
            strongest = strongest ?? candidate.kind
            if collected == nil {
                collected = collect(scope: scope, in: application)
                if let failure = collected?.failure {
                    return failed(failure, attempts: attempts)
                }
            }
            guard let entries = collected?.entries else { continue }
            guard Self.applies(candidate.kind, to: scope) else {
                attempts.append(LocatorAttempt(kind: candidate.kind, outcome: .notApplicable))
                continue
            }
            let hits = entries.filter { Self.matches(candidate.locator, entry: $0) }
            switch hits.count {
            case 0:
                attempts.append(LocatorAttempt(kind: candidate.kind, outcome: .notFound))
            case 1:
                attempts.append(LocatorAttempt(kind: candidate.kind, outcome: .matched))
                let hit = hits[0]
                if hit.facts.isSecure { return failed(.secureField, attempts: attempts) }
                return StepResolution(
                    element: hit.node, matchedKind: candidate.kind, isEnabled: hit.facts.isEnabled,
                    attempts: attempts, failure: nil, isDegraded: candidate.kind != strongest)
            default:
                attempts.append(LocatorAttempt(kind: candidate.kind, outcome: .ambiguous(count: hits.count)))
            }
        }
        let anyAmbiguous = attempts.contains {
            if case .ambiguous = $0.outcome { return true }
            return false
        }
        return failed(anyAmbiguous ? .ambiguous : .notFound, attempts: attempts)
    }

    private func failed(_ failure: StepResolveFailure, attempts: [LocatorAttempt]) -> StepResolution {
        StepResolution(
            element: nil, matchedKind: nil, isEnabled: false, attempts: attempts, failure: failure, isDegraded: false)
    }

    private static func applies(_ kind: LocatorKind, to scope: Scope) -> Bool {
        switch scope {
        case .menuBar: true
        case .windows: kind == .identifier || kind == .roleTitle
        }
    }

    // MARK: Listing

    /// What the recorder needs to know about one leaf menu item: where it is, what it is called and which key it
    /// advertises. Plain values; the Apple menu and menus of recent items are never listed.
    public struct MenuItemInfo: Equatable, Sendable {
        /// Titles of the menus above the item, then its own: `["File", "Export as PDF"]`.
        public let path: [String]
        public let identifier: String
        public let shortcut: KeyShortcut?
        public let isEnabled: Bool
    }

    /// Every leaf item of the app's menu bar, within the budget. Empty when the app has no readable menu bar.
    public func menuItems(in application: any AXNode) -> [MenuItemInfo] {
        let collected = collectMenuItems(in: application)
        return collected.entries.map {
            MenuItemInfo(
                path: $0.path, identifier: $0.facts.identifier, shortcut: $0.facts.shortcut,
                isEnabled: $0.facts.isEnabled)
        }
    }

    // MARK: Matching

    private static func matches(_ locator: StepLocator, entry: Entry) -> Bool {
        switch locator {
        case .identifier(let value):
            return !entry.facts.identifier.isEmpty && entry.facts.identifier == value
        case .roleTitle(let role, let title):
            return entry.facts.role == role && StepText.normalize(entry.facts.title) == StepText.normalize(title)
        case .menuPath(let titles):
            return entry.path.map(StepText.normalize) == titles.map(StepText.normalize)
        case .shortcut(let key, let modifiers):
            guard let shortcut = entry.facts.shortcut else { return false }
            return shortcut.key == key.uppercased() && shortcut.modifiers == modifiers
        case .position(let path):
            return entry.indexPath == path
        case .unsupported:
            return false
        }
    }

    // MARK: Collecting

    struct Entry {
        let node: any AXNode
        let facts: NodeFacts
        /// Titles of the menus above the item, then its own: `["File", "Export as PDF"]`. Empty outside the menu bar.
        let path: [String]
        /// Index in the menu bar, then in each menu below it. Empty outside the menu bar.
        let indexPath: [Int]
    }

    struct Collected {
        var entries: [Entry] = []
        var failure: StepResolveFailure?
    }

    private func collect(scope: Scope, in application: any AXNode) -> Collected {
        switch scope {
        case .menuBar: collectMenuItems(in: application)
        case .windows: collectWindowElements(in: application)
        }
    }

    /// Leaf items of the menu bar, without the Apple menu and without any menu of recent items.
    private func collectMenuItems(in application: any AXNode) -> Collected {
        guard let bar = application.node(StepAX.menuBar) else { return Collected(entries: [], failure: .noMenuBar) }
        var result = Collected()
        var visited = 0
        func walk(_ node: any AXNode, path: [String], indexPath: [Int], depth: Int) -> Bool {
            // `node` is a menu bar item or a menu item; its submenu is the AXMenu child, items are that menu's children.
            for menu in node.nodes(AXAttr.children) {
                for (index, item) in menu.nodes(AXAttr.children).enumerated() {
                    visited += 1
                    if visited > budget.maxNodes || budget.isExpired() { return false }
                    let facts = StepNodeReader.facts(of: item)
                    let title = facts.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if title.isEmpty { continue }
                    if StepText.isRecentMenuTitle(title) || StepText.isRecentMenuIdentifier(facts.identifier) {
                        continue
                    }
                    let here = indexPath + [index]
                    let hasSubmenu = (item.count(AXAttr.children) ?? item.nodes(AXAttr.children).count) > 0
                    if hasSubmenu {
                        if depth < budget.maxDepth, !walk(item, path: path + [title], indexPath: here, depth: depth + 1)
                        {
                            return false
                        }
                    } else {
                        result.entries.append(
                            Entry(node: item, facts: facts, path: path + [title], indexPath: here))
                    }
                }
            }
            return true
        }
        for (index, barItem) in bar.nodes(AXAttr.children).enumerated() {
            // The first item is the Apple menu in every language.
            if index == 0 { continue }
            visited += 1
            if visited > budget.maxNodes || budget.isExpired() {
                result.failure = .budgetExceeded
                return result
            }
            let facts = StepNodeReader.facts(of: barItem)
            let title = facts.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || StepText.isAppleMenuTitle(title) { continue }
            if !walk(barItem, path: [title], indexPath: [index], depth: 1) {
                result.failure = .budgetExceeded
                return result
            }
        }
        if result.entries.isEmpty { result.failure = .noMenuBar }
        return result
    }

    /// Every element of every window, breadth first. Used for expectations; password fields are included only so a
    /// locator that points at one is refused.
    private func collectWindowElements(in application: any AXNode) -> Collected {
        var result = Collected()
        var level = application.nodes(AXAttr.windows)
        var visited = 0
        var depth = 1
        while !level.isEmpty, depth <= budget.maxDepth {
            var next: [any AXNode] = []
            for node in level {
                visited += 1
                if visited > budget.maxNodes || budget.isExpired() {
                    result.failure = .budgetExceeded
                    return result
                }
                let facts = StepNodeReader.facts(of: node)
                result.entries.append(Entry(node: node, facts: facts, path: [], indexPath: []))
                if !facts.isSecure { next += node.nodes(AXAttr.children) }
            }
            level = next
            depth += 1
        }
        return result
    }
}
