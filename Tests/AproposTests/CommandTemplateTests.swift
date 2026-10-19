import Foundation
import Testing

@testable import Apropos

@Suite @MainActor struct CommandTemplateTests {
    @Test func everyTemplateIsAccepted() throws {
        #expect(CommandTemplate.all.count == 4)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString)")
        let store = UserCommandStore(directory: directory)
        for template in CommandTemplate.all {
            let made = try store.create(template.command())
            #expect(made.title == template.title)
            #expect(made.isRunnable || made.runsScripts)
        }
        #expect(store.commands.count == 4)
    }

    @Test func eachAddGetsAFreshID() {
        let first = CommandTemplate.all[0].command()
        let second = CommandTemplate.all[0].command()
        #expect(first.id != second.id)
    }
}
