import Foundation

/// One child process to run. There is never a shell in between unless the caller names one as the executable, and
/// then the script is the caller's literal text: values travel in `arguments`, `environment` and `standardInput`,
/// never spliced into program text.
public struct ProcessRequest: Sendable {
    public var executable: String
    public var arguments: [String]
    /// Added to a minimal base environment (`PATH`, `HOME`, `LANG`); the parent's environment is not inherited.
    public var environment: [String: String]
    public var standardInput: Data?
    public var workingDirectory: String?
    public var timeout: TimeInterval
    /// Output beyond this many bytes ends the run with `.outputTooLarge`.
    public var outputLimit: Int

    public init(
        executable: String, arguments: [String] = [], environment: [String: String] = [:],
        standardInput: Data? = nil, workingDirectory: String? = nil, timeout: TimeInterval = 10,
        outputLimit: Int = 1_000_000
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.outputLimit = outputLimit
    }
}

public struct ProcessOutput: Sendable, Equatable {
    public let status: Int32
    public let standardOutput: Data
    /// How many bytes the process wrote to standard error. The bytes are dropped: they can echo the input.
    public let standardErrorByteCount: Int

    public var text: String { String(decoding: standardOutput, as: UTF8.self) }

    public init(status: Int32, standardOutput: Data, standardErrorByteCount: Int) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardErrorByteCount = standardErrorByteCount
    }
}

public enum ProcessRunError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
    case cancelled
    case outputTooLarge
}

/// Runs a child process off the calling thread, with a hard timeout, cancellation and an output cap.
public enum ProcessRunner {
    public static func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        let job = Job(request)
        return try await withTaskCancellationHandler {
            try await job.start()
        } onCancel: {
            job.cancel()
        }
    }

    private final class Job: @unchecked Sendable {
        private let request: ProcessRequest
        private let process = Process()
        private let lock = NSLock()
        private var stdout = Data()
        private var errorBytes = 0
        private var failure: ProcessRunError?
        private var continuation: CheckedContinuation<ProcessOutput, Error>?
        private var finished = false
        private var cancelledEarly = false

        init(_ request: ProcessRequest) { self.request = request }

        func start() async throws -> ProcessOutput {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                lock.lock()
                self.continuation = continuation
                let early = cancelledEarly
                lock.unlock()
                if early {
                    finish(throwing: .cancelled)
                    return
                }
                launch()
            }
        }

        func cancel() {
            lock.lock()
            cancelledEarly = true
            let running = process.isRunning
            if failure == nil { failure = .cancelled }
            lock.unlock()
            if running { terminate() }
        }

        private func launch() {
            process.executableURL = URL(fileURLWithPath: request.executable)
            process.arguments = request.arguments
            var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
            environment["HOME"] = NSHomeDirectory()
            for (key, value) in request.environment { environment[key] = value }
            process.environment = environment
            if let directory = request.workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self.lock.lock()
                self.stdout.append(chunk)
                let tooBig = self.stdout.count > self.request.outputLimit
                if tooBig, self.failure == nil { self.failure = .outputTooLarge }
                self.lock.unlock()
                if tooBig { self.terminate() }
            }
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                self?.lock.lock()
                self?.errorBytes += chunk.count
                self?.lock.unlock()
            }
            process.terminationHandler = { [weak self] process in
                // Let the readers drain what is left in the pipes before reporting.
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let rest = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errRest = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                self?.complete(status: process.terminationStatus, tail: rest, errorTail: errRest.count)
            }

            do {
                try process.run()
            } catch {
                finish(throwing: .launchFailed)
                return
            }
            let input = request.standardInput
            DispatchQueue.global(qos: .userInitiated).async {
                if let input, !input.isEmpty { try? inPipe.fileHandleForWriting.write(contentsOf: input) }
                try? inPipe.fileHandleForWriting.close()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + request.timeout) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let running = self.process.isRunning
                if running, self.failure == nil { self.failure = .timedOut }
                self.lock.unlock()
                if running { self.terminate() }
            }
        }

        /// SIGTERM, then SIGKILL if the process ignores it.
        private func terminate() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.process.isRunning == true { kill(pid, SIGKILL) }
            }
        }

        private func complete(status: Int32, tail: Data, errorTail: Int) {
            lock.lock()
            stdout.append(tail)
            errorBytes += errorTail
            let failure = self.failure ?? (stdout.count > request.outputLimit ? .outputTooLarge : nil)
            let output = ProcessOutput(status: status, standardOutput: stdout, standardErrorByteCount: errorBytes)
            lock.unlock()
            if let failure {
                finish(throwing: failure)
            } else {
                finish(returning: output)
            }
        }

        private func finish(returning output: ProcessOutput) {
            lock.lock()
            guard !finished, let continuation else {
                lock.unlock()
                return
            }
            finished = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: output)
        }

        private func finish(throwing error: ProcessRunError) {
            lock.lock()
            guard !finished, let continuation else {
                lock.unlock()
                return
            }
            finished = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: error)
        }
    }
}
