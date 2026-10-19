import Apropos
import SwiftUI

/// What the recording bar and the permission screen can do. The coordinator supplies them; previews leave them empty.
struct RecordingActions {
    var stop: () -> Void = {}
    var cancel: () -> Void = {}
    var openDraft: () -> Void = {}
    var dismiss: () -> Void = {}
    var allow: (RecordingPermissionKind) -> Void = { _ in }
    var start: () -> Void = {}
    var saveReview: () -> Void = {}
    var addReviewToDraft: () -> Void = {}
    var discardReview: () -> Void = {}
}

/// The recording bar: a small glass pill that floats near the top of the screen. The pearl pulses while it listens, the
/// time and the step count run, and Stop is one press. It never takes focus, so the app being recorded stays in front.
/// After the recording it says what happened in a line, and offers the draft.
struct RecordingBarView: View {
    let model: RecordingModel
    let stopKeys: [String]
    let actions: RecordingActions

    static let width: CGFloat = 420

    var body: some View {
        Group {
            switch model.phase {
            case .recording: live
            case .finished(let outcome): result(outcome.message, symbol: outcome.addedToDraft ? "checkmark" : "info.circle", open: outcome.addedToDraft)
            case .failed(let message): result(message, symbol: "exclamationmark.triangle.fill", open: false)
            case .idle, .needsPermission, .reviewing: EmptyView()
            }
        }
        .frame(width: Self.width)
    }

    // MARK: Listening

    private var live: some View {
        HStack(spacing: 10) {
            PearlView(size: 8, pulsing: !model.pausedForSecureInput)
                .opacity(model.pausedForSecureInput ? 0.4 : 1)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.pausedForSecureInput ? "Paused, password field" : "Recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(detail)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Brand.text3)
            }
            Spacer(minLength: 8)
            Button(action: actions.stop) {
                HStack(spacing: 6) {
                    Text("Stop").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    ForEach(Array(stopKeys.enumerated()), id: \.offset) { KeyCap(text: $0.element, small: true) }
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .help("Stop and keep what was recorded")
            Button(action: actions.cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel and throw the recording away")
            .accessibilityLabel("Cancel recording")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 50)
        .aproposGlass(in: Capsule())
        .accessibilityElement(children: .contain)
    }

    /// "0:42 · 3 steps", counting down in the last half minute.
    private var detail: String {
        let steps = "\(model.stepCount) step\(model.stepCount == 1 ? "" : "s")"
        let remaining = model.maxDuration - model.elapsed
        if remaining <= 30 { return "\(Self.clock(max(remaining, 0))) left · \(steps)" }
        return "\(Self.clock(model.elapsed)) · \(steps)"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: Done

    private func result(_ message: String, symbol: String, open: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbol == "checkmark" ? Brand.mint : Brand.text2)
                .frame(width: 18)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if open {
                Button("Open draft", action: actions.openDraft)
                    .buttonStyle(CapsuleButtonStyle())
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Button(action: actions.dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .aproposGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The screen that names the two permissions a recording needs, says what each allows, what is never kept, and opens the
/// right page of System Settings. Nothing is requested until the person presses Allow, and Apropos checks again once a
/// second so the row turns green as soon as the switch is on.
struct RecordingPermissionView: View {
    let model: RecordingModel
    let actions: RecordingActions

    static let size = CGSize(width: 500, height: 660)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandGlyph().foregroundStyle(Brand.text).frame(width: 22, height: 22)
                Text(RecordingPermissionCopy.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.text)
            }
            Text(RecordingPermissionCopy.summary)
                .font(.system(size: 13))
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(RecordingPermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(Brand.line) }
                    row(kind)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.section))
            .padding(.top, 16)

            Text("What is never kept")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.text2)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(RecordingPermissionCopy.neverStored, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Brand.text3).frame(width: 4, height: 4).offset(y: -2)
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 6)

            Text(RecordingPermissionCopy.notRequested + " After allowing Input Monitoring, macOS may ask you to quit and reopen Apropos.")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Spacer()
                Button("Not now", action: actions.dismiss)
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
                Button("Start recording", action: actions.start)
                    .buttonStyle(BrandButtonStyle(kind: .primary))
                    .disabled(!model.status.canRecord)
                    .opacity(model.status.canRecord ? 1 : 0.5)
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(WindowBackdrop().ignoresSafeArea())
        .tint(Brand.mint)
        .ignoresSafeArea()
    }

    private func row(_ kind: RecordingPermissionKind) -> some View {
        let granted = model.status.isGranted(kind)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(granted ? Brand.mint : Brand.text3)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(kind.whatItAllows)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Why: " + kind.whyRecording)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.mint)
            } else {
                Button("Allow") { actions.allow(kind) }
                    .buttonStyle(BrandButtonStyle(kind: .secondary))
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

/// The review of a finished recording: every step in plain words with a badge for how reliably it will be found again, what
/// was left out, small edits, a look at the steps against the apps as they are now, and a form that saves them as a command.
struct RecordingReviewView: View {
    let review: RecordingReview
    var actions: RecordingActions = RecordingActions()
    var shortcutRecording: (Bool) -> Void = { _ in }

    static let size = CGSize(width: 600, height: 700)

    @State private var editing: Int?
    @State private var draftText = ""

    var body: some View {
        @Bindable var review = review
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandGlyph().foregroundStyle(Brand.text).frame(width: 22, height: 22)
                Text("Review what you recorded")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.text)
            }
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(review.notes(after: nil)) { noteRow($0) }
                    ForEach(Array(review.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 || !review.notes(after: nil).isEmpty { Divider().overlay(Brand.line) }
                        itemRow(item, isFirst: index == 0, isLast: index == review.items.count - 1)
                        ForEach(review.notes(after: item.id)) { noteRow($0) }
                    }
                    if review.items.isEmpty {
                        Text("Nothing left. Discard this, or record again.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Brand.text3)
                            .padding(20)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.section))
            .padding(.top, 14)

            form
                .padding(.top, 16)
            if let problem = review.problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } else if let blocker = review.blocker {
                Text(blocker).font(.system(size: 12)).foregroundStyle(Brand.text3).padding(.top, 8)
            }
            buttons
                .padding(.top, 12)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(WindowBackdrop().ignoresSafeArea())
        .tint(Brand.mint)
        .ignoresSafeArea()
    }

    private var subtitle: String {
        let steps = "\(review.stepCount) step\(review.stepCount == 1 ? "" : "s")"
        var text = "\(steps). Fix what is off, then save it as a command."
        if review.textEntryCount > 0 { text += " What you typed was not recorded and will be left out." }
        return text
    }

    // MARK: Rows

    private func itemRow(_ item: DraftItem, isFirst: Bool, isLast: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: item))
                .font(.system(size: 13))
                .foregroundStyle(Brand.text2)
                .frame(width: 20)
            if editing == item.id {
                TextField("What this step does", text: $draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { commitRename(item.id) }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.raised))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.summary)
                        .font(.system(size: 13, weight: item.step == nil ? .regular : .medium))
                        .foregroundStyle(item.step == nil ? Brand.text2 : Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = item.originNote {
                        Text(note).font(.system(size: 11.5)).foregroundStyle(Brand.text3)
                    }
                }
            }
            Spacer(minLength: 6)
            badge(for: item)
            Button {
                review.moveUp(item.id)
            } label: {
                Image(systemName: "chevron.up").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFirst ? Brand.text3.opacity(0.4) : Brand.text2)
            .disabled(isFirst)
            .accessibilityLabel("Move up")
            Button {
                review.moveDown(item.id)
            } label: {
                Image(systemName: "chevron.down").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLast ? Brand.text3.opacity(0.4) : Brand.text2)
            .disabled(isLast)
            .accessibilityLabel("Move down")
            Menu {
                if item.step != nil {
                    Button("Rename") {
                        draftText = item.summary
                        editing = item.id
                    }
                }
                if review.canMerge(item.id) { Button("Merge with the next row") { review.merge(item.id) } }
                Button("Delete", role: .destructive) { review.delete(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.text2)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func noteRow(_ note: SkippedNote) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 11.5)).foregroundStyle(Brand.text3).frame(width: 20)
            Text(note.text).font(.system(size: 11.5)).foregroundStyle(Brand.text3)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func symbol(for item: DraftItem) -> String {
        switch item.content {
        case .step(_, let origin): origin == .shortcut ? "command" : "cursorarrow.click"
        case .appSwitch: "arrow.triangle.swap"
        case .textEntered: "text.cursor"
        }
    }

    /// After "Try it" the answer for each step; before it how sturdy the step is.
    @ViewBuilder
    private func badge(for item: DraftItem) -> some View {
        if let check = review.checks[item.id] {
            switch check {
            case .found: Badge(text: "Found", tone: .mint)
            case .weak: Badge(text: "Found by title only", tone: .warning)
            case .missing(let why): Badge(text: "Not found", tone: .warning).help(why)
            case .unchecked(let why): Badge(text: "Cannot check", tone: .quiet).help(why)
            }
        } else if let fragility = item.fragility {
            Badge(text: fragility.title, tone: fragility == .sturdy ? .mint : (fragility == .fair ? .quiet : .warning))
                .help(fragility.explanation)
        }
    }

    private func commitRename(_ id: Int) {
        review.rename(id, to: draftText)
        editing = nil
    }

    // MARK: Form and buttons

    private var form: some View {
        @Bindable var review = review
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labelled("Name") {
                    TextField("Name this command", text: $review.name).field()
                }
                labelled("Alias") {
                    TextField("Optional, typed to find it", text: $review.alias).field().frame(width: 190)
                }
            }
            labelled("Shortcut") {
                ShortcutRecorder(
                    combo: review.hotkey, placeholder: "Optional", minWidth: 140,
                    onRecordingChange: shortcutRecording, onChange: { review.hotkey = $0 },
                    onClear: { review.hotkey = nil })
            }
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text2)
            content()
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Try it") { review.check() }
                .buttonStyle(BrandButtonStyle(kind: .secondary))
                .help("Look for every step in the apps as they are now, without pressing anything")
                .disabled(review.stepCount == 0)
            Button("Discard", action: actions.discardReview)
                .buttonStyle(BrandButtonStyle(kind: .plain))
            Spacer()
            Button("Add to draft instead", action: actions.addReviewToDraft)
                .buttonStyle(BrandButtonStyle(kind: .secondary))
                .disabled(review.stepCount == 0)
            Button("Save command", action: actions.saveReview)
                .buttonStyle(BrandButtonStyle(kind: .primary))
                .disabled(!review.canSave)
                .opacity(review.canSave ? 1 : 0.5)
        }
    }
}

extension TextField {
    /// The look of a plain field in a form: a soft rounded tile.
    fileprivate func field() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.raised))
    }
}
