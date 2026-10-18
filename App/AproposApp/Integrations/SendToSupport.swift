import AppKit
import Apropos
import Foundation

/// Shows the system Share menu for a payload, anchored to the palette. The panel sets `anchor` once it has a view.
@MainActor
final class ShareMenuPresenter: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    weak var anchor: NSView?
    private var continuation: CheckedContinuation<ShareResult, Never>?

    func present(_ payload: Payload) async -> ShareResult {
        guard let anchor, continuation == nil else { return .unavailable }
        let picker = NSSharingServicePicker(items: Self.items(for: payload))
        picker.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let bounds = anchor.bounds
            picker.show(
                relativeTo: NSRect(x: bounds.midX, y: bounds.minY + 60, width: 1, height: 1), of: anchor,
                preferredEdge: .minY)
        }
    }

    /// Called with a service when the person chose one (the picker then performs it) and with nil when the menu closed.
    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        continuation?.resume(returning: service == nil ? .dismissed : .shared)
        continuation = nil
    }

    private static func items(for payload: Payload) -> [Any] {
        switch payload.kind {
        case .text:
            var items: [Any] = [payload.text ?? ""]
            if let url = payload.url { items.append(url as NSURL) }
            return items
        case .page:
            return payload.url.map { [$0 as NSURL] } ?? []
        case .files:
            return payload.files.map { $0 as NSURL }
        case .folder:
            return payload.folder.map { [$0 as NSURL] } ?? []
        }
    }
}

/// Asks for a folder the first time files are copied or moved somewhere.
@MainActor
enum FolderChooser {
    static func choose(move: Bool) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = move ? "Choose the folder to move the files into." : "Choose the folder to copy the files into."
        panel.prompt = move ? "Move Here" : "Copy Here"
        NSApp.activate()
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}

/// The send services of the running app, and a harmless set for agent mode.
@MainActor
enum AppSendServices {
    static func live(presenter: ShareMenuPresenter) -> SendServices {
        var services = SendServices.live
        services.share = { payload in await presenter.present(payload) }
        return services
    }

    #if DEBUG
        /// Services that touch nothing: every app counts as installed, no process runs, no link opens and the Share
        /// menu is not shown. With `failing` they report failure so the error state can be looked at. Used by previews
        /// and agent mode, which must never create a note, open a draft or copy a file in the person's apps.
        static func fake(failing: Bool = false) -> SendServices {
            var actions = ActionServices.live
            actions.process = { _ in
                ProcessOutput(status: failing ? 1 : 0, standardOutput: Data(), standardErrorByteCount: 0)
            }
            actions.openURL = { _ in !failing }
            return SendServices(isInstalled: { _ in true }, share: { _ in .shared }, actions: actions)
        }

        /// Agent mode: APROPOS_FIXTURE_SEND_FAIL=1 makes sending fail.
        static func agent() -> SendServices {
            fake(failing: ProcessInfo.processInfo.environment["APROPOS_FIXTURE_SEND_FAIL"] != nil)
        }
    #endif
}
