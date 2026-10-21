import Foundation

/// Every address the app points people to, in one place so the About page, the menus and the tests agree.
enum ProjectLinks {
    static let author = "Walid Zakan"
    static let authorHandle = "Zawalid"

    enum Link: CaseIterable {
        case authorGitHub, authorWebsite, authorX, website, repository, issues, newIssue, license

        var title: String {
            switch self {
            case .authorGitHub: "GitHub"
            case .authorWebsite: "zawalid.com"
            case .authorX: "X"
            case .website: "apropos.zawalid.com"
            case .repository: "Source code"
            case .issues: "Report an issue"
            case .newIssue: "New issue"
            case .license: "MIT license"
            }
        }

        var symbol: String {
            switch self {
            case .authorGitHub: "chevron.left.forwardslash.chevron.right"
            case .authorWebsite: "globe"
            case .authorX: "at"
            case .website: "safari"
            case .repository: "curlybraces"
            case .issues, .newIssue: "exclamationmark.bubble"
            case .license: "doc.text"
            }
        }

        var url: URL {
            let address: String
            switch self {
            case .authorGitHub: address = "https://github.com/Zawalid"
            case .authorWebsite: address = "https://zawalid.com"
            case .authorX: address = "https://x.com/Zawaalid"
            case .website: address = "https://apropos.zawalid.com"
            case .repository: address = "https://github.com/Zawalid/Apropos"
            case .issues: address = "https://github.com/Zawalid/Apropos/issues"
            case .newIssue: address = "https://github.com/Zawalid/Apropos/issues/new/choose"
            case .license: address = "https://github.com/Zawalid/Apropos/blob/main/LICENSE"
            }
            return URL(string: address) ?? URL(fileURLWithPath: "/")
        }
    }
}
