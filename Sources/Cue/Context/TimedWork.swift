import Foundation

/// Runs blocking work on a background queue and gives up waiting after a deadline. The work itself cannot be
/// cancelled (an Accessibility call blocks until the app answers or its messaging timeout fires), but the caller
/// stops waiting and the late result is dropped.
enum TimedWork {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// Returns the work's result, or nil when the deadline passed first.
    static func run<T: Sendable>(
        timeout: TimeInterval, queue: DispatchQueue = .global(qos: .userInitiated),
        _ work: @escaping @Sendable () -> T
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = Once()
            queue.async {
                let value = work()
                if once.claim() { continuation.resume(returning: value) }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}
