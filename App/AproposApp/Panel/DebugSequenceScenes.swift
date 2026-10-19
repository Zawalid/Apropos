#if DEBUG
    import Apropos
    import Foundation

    /// Which state of the sequence builder a palette scene shows.
    enum SequenceScene: String {
        /// The list with the draft row at the head.
        case row
        /// The draft level: Run, Save, Discard and the steps.
        case level
        /// The combined confirmation waiting for its Return.
        case confirm
        /// A question asked in the search field before the run.
        case ask
        /// A run that stopped at a step, with the steps marked.
        case failure
        /// The form that saves the draft as a command.
        case save
        /// The list again, with the notice of where the command went.
        case saved
        /// The draft level with four steps: two menu items, the second one added twice, then an action.
        case menus
        /// The same draft after the selection went away: the step that reads text says so.
        case menusMissing
        /// The form with the symbol row collapsed, the keyboard on it and the choice moved one place on.
        case saveQuick
        /// The form with the symbol search holding "mail" and the choice moved one place on.
        case saveSearch
        /// The form with a symbol name typed that the curated list does not have.
        case saveCustom
        /// The form with a search nothing matches.
        case saveNoMatch
        /// The form with the keyboard in the symbol grid and the choice moved down a row.
        case saveGrid

        /// Whether the keyboard sits in the symbol field, so its ring is drawn.
        var focusesSymbol: Bool { [.saveQuick, .saveSearch, .saveCustom, .saveNoMatch, .saveGrid].contains(self) }
    }

    /// Debug builds only: puts the palette into one state of the sequence builder by doing what a person would do, through
    /// the real model, over fake services. The draft is "uppercase, then send to Notes" (Mail for the confirmation).
    @MainActor
    enum DebugSequences {
        /// Builds the sample draft and walks to `scene`. The palette must already hold a snapshot with a selection.
        static func apply(_ scene: SequenceScene, model: PaletteModel) async {
            guard let sequences = model.sequences else { return }
            func row(_ id: String) -> Command? { model.results.first { $0.command.id == id }?.command }

            if scene == .menus || scene == .menusMissing {
                // The preview menu has no real app behind it, so the menu steps are added the way the recorder hands
                // them over: one step each, the second one twice.
                func menu(_ path: [String]) -> UIStep {
                    UIStep(
                        app: "com.apple.Safari", locators: [.menuPath(path)],
                        description: "Choose \(path.joined(separator: " > ")) in Safari")
                }
                sequences.add(uiSteps: [menu(["File", "New Window"])], label: "New Window")
                sequences.add(uiSteps: [menu(["View", "Show Sidebar"])], label: "Show Sidebar")
                sequences.add(uiSteps: [menu(["View", "Show Sidebar"])], label: "Show Sidebar")
                if let upper = row("ctx:text.upper") { model.addToSequence(upper) }
                if let top = model.results.first?.command { _ = await model.run(top) }
                if scene == .menusMissing {
                    sequences.update(
                        with: ContextSnapshot(
                            appName: "Safari", bundleID: "com.apple.Safari", pid: 0,
                            capturedAt: Date().addingTimeInterval(5), values: ContextValues()))
                }
                return
            }
            guard let upper = row("ctx:text.upper") else { return }
            model.addToSequence(upper)
            // A destination is added from the destination list, the way a person adds it.
            guard let generic = row("send:text") else { return }
            _ = await model.run(generic)
            if let destination = row(scene == .confirm ? "send:text>dest:mail" : "send:text>dest:notes") {
                model.addToSequence(destination)
            }
            _ = model.goBack()
            if scene == .row { return }

            if scene == .ask, let first = sequences.steps.first { sequences.setAsking(true, stepID: first.id) }
            guard let top = model.results.first?.command else { return }
            _ = await model.run(top)
            if scene == .level { return }
            if scene == .save || scene == .saved || scene.focusesSymbol {
                if let save = row("seq:save") { _ = await model.run(save) }
                // The grid scenes show the opened grid; the others show the one-line row.
                if scene.focusesSymbol && scene != .saveQuick { sequences.expandSymbols() }
                switch scene {
                case .saveQuick: sequences.symbolKey(.right)
                case .saveSearch:
                    sequences.form.symbolQuery = "mail"
                    sequences.moveSymbol(.right)
                case .saveCustom: sequences.form.symbolQuery = "folder.badge.gearshape"
                case .saveNoMatch: sequences.form.symbolQuery = "zzzzqx"
                case .saveGrid:
                    sequences.moveSymbol(.down)
                    sequences.moveSymbol(.right)
                default: break
                }
                if scene == .saved {
                    sequences.form.name = "Shout and note"
                    sequences.form.alias = "shout"
                    model.saveSequence()
                }
                return
            }
            // confirm, ask and failure all start with Run.
            if let run = row("seq:run") { _ = await model.run(run) }
        }
    }
#endif
