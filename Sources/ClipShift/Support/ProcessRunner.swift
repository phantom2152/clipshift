import Foundation

struct ProcessResult: Sendable {
    var status: Int32
    var wasCancelled: Bool
    var errorText: String
}

/// Runs one external process (ffmpeg or yt-dlp) and streams its stdout line by line.
/// Thread-safe, so `cancel()` can be called from the UI.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var stderrTail = ""
    private let splitter = LineSplitter()
    private let stderrLimit: Int
    private let gracefulCancel: Bool

    /// - Parameters:
    ///   - stderrLimit: how many trailing characters of stderr to keep for error messages.
    ///   - gracefulCancel: send SIGINT first (yt-dlp cleans up), then SIGTERM after 3 s.
    init(stderrLimit: Int = 2000, gracefulCancel: Bool = false) {
        self.stderrLimit = stderrLimit
        self.gracefulCancel = gracefulCancel
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        if gracefulCancel {
            p.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if p.isRunning { p.terminate() }
            }
        } else {
            p.terminate()
        }
    }

    // MARK: Output handling

    /// Splits a chunk into lines and hands each non-empty, trimmed line to `onLine`.
    private func drain(_ chunk: Data, flush: Bool, _ onLine: (String) -> Void) {
        lock.lock()
        var lines = splitter.feed(chunk)
        if flush, let rest = splitter.flush() { lines.append(rest) }
        lock.unlock()

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { onLine(line) }
        }
    }

    private func appendErr(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock()
        stderrTail += String(decoding: d, as: UTF8.self)
        if stderrTail.count > stderrLimit { stderrTail = String(stderrTail.suffix(stderrLimit)) }
        lock.unlock()
    }

    private func currentErr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrTail
    }

    private func clearProcess() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    // MARK: Running

    /// `extraPath` directories are added to PATH, because GUI apps start with a minimal one
    /// and yt-dlp may need to find helpers (ffmpeg, a JavaScript runtime) next to itself.
    func run(
        executable: String, arguments: [String], extraPath: [String] = [],
        onLine: @escaping @Sendable (String) -> Void
    ) async -> ProcessResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            if !extraPath.isEmpty {
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (extraPath + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
                p.environment = env
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            p.standardInput = FileHandle.nullDevice

            outPipe.fileHandleForReading.readabilityHandler = { [self] h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                drain(d, flush: false, onLine)
            }
            errPipe.fileHandleForReading.readabilityHandler = { [self] h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                appendErr(d)
            }

            p.terminationHandler = { [self] proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // The last lines (for yt-dlp, the final file path) arrive right before exit.
                drain(outPipe.fileHandleForReading.readDataToEndOfFile(), flush: true, onLine)
                appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

                // Close the pipes and drop the handler so the runner, the process and its
                // file descriptors don't outlive the job (the handler captures `self`).
                try? outPipe.fileHandleForReading.close()
                try? errPipe.fileHandleForReading.close()
                proc.terminationHandler = nil
                clearProcess()

                cont.resume(
                    returning: ProcessResult(
                        status: proc.terminationStatus,
                        wasCancelled: isCancelled,
                        errorText: currentErr()))
            }

            lock.lock()
            if cancelled {
                lock.unlock()
                cont.resume(returning: ProcessResult(status: -1, wasCancelled: true, errorText: ""))
                return
            }
            process = p
            lock.unlock()

            do {
                try p.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                p.terminationHandler = nil
                clearProcess()
                cont.resume(
                    returning: ProcessResult(
                        status: -1, wasCancelled: false,
                        errorText: error.localizedDescription))
                return
            }

            // A cancel() that landed between storing the process and launching it.
            if isCancelled, p.isRunning { p.terminate() }
        }
    }
}

// MARK: - One-shot capture

extension ProcessRunner {
    enum Stream { case stdout, stderr }

    /// Runs a short command to completion and returns what it printed on one stream,
    /// or nil if it could not be launched. Meant for `--version` and `ffmpeg -i` style calls.
    static func capture(_ executable: String, _ arguments: [String], stream: Stream) async
        -> String?
    {
        await Task.detached { () -> String? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            p.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            switch stream {
            case .stdout:
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
            case .stderr:
                p.standardOutput = FileHandle.nullDevice
                p.standardError = pipe
            }
            do { try p.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
