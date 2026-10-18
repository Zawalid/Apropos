import AppKit
import Apropos
import UniformTypeIdentifiers

/// Managing commands from the menu bar until Settings has a page for it: open the folder, reload after editing by hand,
/// import and export a file, and approve commands that came from an import. Each step that runs or approves anything
/// shows what the command does first (`CommandSummary`).
@MainActor
enum CommandManagement {
    static func reveal(_ store: UserCommandStore) {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.directory)
    }

    static func reload(_ store: UserCommandStore) {
        store.reload()
        if !store.issues.isEmpty {
            let count = store.issues.count
            Task { await ActionServices.live.notify("\(count) command file\(count == 1 ? "" : "s") could not be used.") }
        }
    }

    // MARK: Import

    static func importCommands(_ store: UserCommandStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Apropos commands file"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let review: ImportReview
        do {
            review = try store.reviewFile(at: url)
        } catch let error as CommandImportError {
            inform("Could not import", error.description)
            return
        } catch {
            inform("Could not import", "That file could not be read.")
            return
        }
        guard !review.items.isEmpty else {
            inform("Nothing to import", rejectionText(review) ?? "The file has no usable commands.")
            return
        }

        var lines: [String] = []
        for item in review.items {
            var line = "\u{2022} \(item.command.title)"
            if let duplicate = item.duplicateOf { line += " (same as \(duplicate), skipped)" }
            if item.needsApproval { line += " (runs scripts: needs your approval after import)" }
            lines.append(line)
        }
        if let rejected = rejectionText(review) { lines.append("\n" + rejected) }
        let alert = NSAlert()
        alert.messageText = "Import \(review.defaultSelection.count) of \(review.items.count) commands?"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let result = store.importReviewed(review)
        let waiting = store.pending.count
        if waiting > 0 {
            inform(
                "Imported \(result.added.count)",
                "\(waiting) command\(waiting == 1 ? " is" : "s are") waiting for your approval and will not run until you approve. Use Review Imported Commands in the menu.")
        } else if !result.failed.isEmpty {
            inform("Imported \(result.added.count)", "\(result.failed.count) could not be saved.")
        }
    }

    private static func rejectionText(_ review: ImportReview) -> String? {
        guard !review.rejected.isEmpty else { return nil }
        return "Not imported:\n" + review.rejected.prefix(5).map { "\u{2022} \($0.title ?? "A command"): \($0.reason)" }.joined(separator: "\n")
    }

    // MARK: Review

    /// Asks about each pending command in turn: what it does, then Approve, Delete or Later.
    static func reviewPending(_ store: UserCommandStore) {
        NSApp.activate()
        for command in store.pending {
            let alert = NSAlert()
            alert.messageText = "Approve \u{201C}\(command.title)\u{201D}?"
            let warnings = CommandSummary.risks(for: command).map(\.warning)
            alert.informativeText = (warnings + [""] + CommandSummary.lines(for: command)).joined(separator: "\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Approve")
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Delete")
            switch alert.runModal() {
            case .alertFirstButtonReturn: _ = try? store.approve(command.id)
            case .alertThirdButtonReturn: try? store.delete(command.id)
            default: break
            }
        }
    }

    // MARK: Export

    static func exportCommands(_ store: UserCommandStore) {
        guard !store.commands.isEmpty else {
            inform("Nothing to export", "You have no commands yet.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Apropos Commands.json"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCommands(to: url)
        } catch {
            inform("Could not export", "The file could not be written.")
        }
    }

    private static func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
