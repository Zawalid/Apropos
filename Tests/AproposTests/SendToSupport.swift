import Foundation

@testable import Apropos

/// A fake for everything sending touches: it records the processes and links the engine asked for and answers as
/// configured, so no test creates a note, opens an app or copies a file.
final class SendRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _processes: [ProcessRequest] = []
    private var _opened: [URL] = []
    private var _shared: [Payload] = []
    var processStatus: Int32 = 0
    var openAnswer = true
    var shareAnswer = ShareResult.shared
    var installed: Set<String> = []

    var processes: [ProcessRequest] { lock.withLock { _processes } }
    var opened: [URL] { lock.withLock { _opened } }
    var shared: [Payload] { lock.withLock { _shared } }

    var services: SendServices {
        SendServices(
            isInstalled: { self.installed.contains($0) },
            share: { payload in
                self.lock.withLock { self._shared.append(payload) }
                return self.shareAnswer
            },
            actions: ActionServices(
                process: { request in
                    self.lock.withLock { self._processes.append(request) }
                    return ProcessOutput(status: self.processStatus, standardOutput: Data(), standardErrorByteCount: 0)
                },
                openURL: { url in
                    self.lock.withLock { self._opened.append(url) }
                    return self.openAnswer
                },
                copyToClipboard: { _ in }, notify: { _ in }, postKey: { _ in true },
                replaceSelection: { _, _ in .failed }))
    }

    var runner: DestinationRunner { DestinationRunner(services: services) }
}

/// Texts that try to become code in a script, a shell, a link or an option list.
let hostileTexts: [String] = [
    "plain",
    "\"; do shell script \"touch /tmp/apropos-pwn\" --",
    "' & do shell script \"touch /tmp/apropos-pwn\" & '",
    "$(touch /tmp/apropos-pwn) `touch /tmp/apropos-pwn` ; | & > < \\ \\n",
    "line one\nline two\r\nline three\ttabbed",
    "-rf --version -e -s x",
    "{text} {{text}} {title} }{ {url}",
    "100% %41 %0A %00 %",
    "a&b=c?d#e/f:g@h",
    "tell application \"Finder\" to delete every item\nend tell",
    "emoji \u{1F600}\u{1F1EB}\u{1F1F7} family \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} caf\u{00E9} \u{202E}rtl",
    String(repeating: "long text with \"quotes\" and \n newlines ", count: 5_000),
]

func destinations(fromPack json: String, origin: DestinationOrigin = .bundled) -> DestinationLibrary {
    var library = DestinationLibrary()
    library.add(packData: Data(json.utf8), source: "test.json", origin: origin)
    return library
}
