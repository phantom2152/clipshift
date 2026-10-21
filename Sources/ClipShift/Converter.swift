import AppKit

struct FFmpegResult: Sendable {
    var status: Int32
    var wasCancelled: Bool
    var errorText: String
}

final class LineSplitter: @unchecked Sendable {
    private var data = Data()
    func feed(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 10) {
            lines.append(String(decoding: data[data.startIndex..<nl], as: UTF8.self))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }
}

/// Runs one ffmpeg process. Thread-safe so cancel() can be called from the UI.
final class FFmpegRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var stderrTail = ""

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
        p?.terminate()
    }

    private func appendErr(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock()
        stderrTail += String(decoding: d, as: UTF8.self)
        if stderrTail.count > 2000 { stderrTail = String(stderrTail.suffix(2000)) }
        lock.unlock()
    }

    private func currentErr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrTail
    }

    /// `onProgress` receives the encoded position in seconds.
    func run(
        ffmpeg: String, args: [String],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> FFmpegResult {
        await withCheckedContinuation { (cont: CheckedContinuation<FFmpegResult, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpeg)
            p.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            p.standardInput = FileHandle.nullDevice

            let splitter = LineSplitter()
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                for line in splitter.feed(d) where line.hasPrefix("out_time_us=") {
                    if let us = Double(line.dropFirst("out_time_us=".count)) {
                        onProgress(us / 1_000_000)
                    }
                }
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
                appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                cont.resume(
                    returning: FFmpegResult(
                        status: proc.terminationStatus,
                        wasCancelled: isCancelled,
                        errorText: currentErr()))
            }

            lock.lock()
            if cancelled {
                lock.unlock()
                cont.resume(returning: FFmpegResult(status: -1, wasCancelled: true, errorText: ""))
                return
            }
            process = p
            lock.unlock()

            do {
                try p.run()
            } catch {
                cont.resume(
                    returning: FFmpegResult(
                        status: -1, wasCancelled: false,
                        errorText: error.localizedDescription))
            }
        }
    }

    /// `ffmpeg -i file` prints "Duration: HH:MM:SS.xx" on stderr; no ffprobe needed.
    static func probeDuration(ffmpeg: String, input: URL) async -> Double? {
        await Task.detached { () -> Double? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpeg)
            p.arguments = ["-hide_banner", "-nostdin", "-i", input.path]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            guard
                let r = text.range(
                    of: #"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#,
                    options: .regularExpression)
            else { return nil }
            let parts = text[r].dropFirst("Duration: ".count).split(separator: ":")
            guard parts.count == 3,
                let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2])
            else { return nil }
            return h * 3600 + m * 60 + s
        }.value
    }
}

@MainActor
final class Job: ObservableObject, Identifiable {
    enum State: Equatable {
        case waiting, running, done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let input: URL
    var runner = FFmpegRunner()
    @Published var state: State = .waiting
    @Published var progress: Double = 0
    @Published var indeterminate = false
    @Published var output: URL?

    init(input: URL) { self.input = input }
}

@MainActor
final class ConversionManager: ObservableObject {
    static let shared = ConversionManager()

    @Published var jobs: [Job] = []
    @Published var isRunning = false
    private var cancelRequested = false

    var hasPending: Bool {
        jobs.contains { job in
            switch job.state {
            case .waiting, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    func add(_ urls: [URL]) {
        var skippedFiles = 0
        var rejectedFolders: [String] = []

        func append(_ url: URL) {
            if jobs.contains(where: { $0.input.path == url.path }) { return }
            jobs.append(Job(input: url))
        }

        for url in urls where url.isFileURL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                continue
            }
            if isDir.boolValue {
                switch MediaFilter.scan(url) {
                case .tooMany: rejectedFolders.append(url.lastPathComponent)
                case .files(let files): files.forEach(append)
                }
            } else if MediaFilter.isMedia(url) {
                append(url)
            } else {
                skippedFiles += 1
            }
        }

        var lines: [String] = []
        if !rejectedFolders.isEmpty {
            lines.append(
                "Too many files in: \(rejectedFolders.joined(separator: ", ")). "
                    + "Folders are limited to \(MediaFilter.maxFolderFiles) media files, so nothing from them was added."
            )
        }
        if skippedFiles > 0 {
            lines.append(
                "Skipped \(skippedFiles) file\(skippedFiles == 1 ? "" : "s") that aren't video or audio."
            )
        }
        if !lines.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some items weren't added"
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.runModal()
        }
    }

    func remove(_ job: Job) {
        guard job.state != .running else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.state == .done }
    }

    func cancelAll() {
        cancelRequested = true
        for job in jobs where job.state == .running { job.runner.cancel() }
    }

    func start(format: OutputFormat, quality: Quality) {
        guard !isRunning else { return }
        for job in jobs {
            if case .failed = job.state { job.state = .waiting }
            if job.state == .cancelled { job.state = .waiting }
        }
        isRunning = true
        cancelRequested = false

        Task {
            var finished: [URL] = []
            while !cancelRequested, let job = jobs.first(where: { $0.state == .waiting }) {
                await convert(job, format: format, quality: quality)
                if job.state == .done, let out = job.output { finished.append(out) }
            }
            isRunning = false

            let s = Settings.shared
            if !finished.isEmpty {
                if s.playSoundWhenDone { NSSound(named: "Glass")?.play() }
                if s.revealWhenDone { NSWorkspace.shared.activateFileViewerSelecting(finished) }
            }
        }
    }

    private func convert(_ job: Job, format: OutputFormat, quality: Quality) async {
        let s = Settings.shared
        let ffmpeg = s.resolvedFFmpegPath
        guard FileManager.default.isExecutableFile(atPath: ffmpeg) else {
            Log.write("ERROR ffmpeg not found at \(ffmpeg)")
            job.state = .failed(
                "ffmpeg not found at \(ffmpeg). Set the correct path in Settings (⌘,).")
            return
        }

        job.runner = FFmpegRunner()
        let runner = job.runner
        job.progress = 0
        job.state = .running

        let out = Self.outputURL(
            for: job.input, format: format,
            folder: s.outputFolder, overwrite: s.overwriteExisting)
        if let folder = s.outputFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let duration = await FFmpegRunner.probeDuration(ffmpeg: ffmpeg, input: job.input)
        job.indeterminate = (duration ?? 0) <= 0
        if runner.isCancelled {
            job.state = .cancelled
            return
        }

        let args =
            [
                "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                "-i", job.input.path, "-progress", "pipe:1", "-nostats",
            ]
            + format.arguments(quality: quality) + [out.path]

        Log.write(
            "START \(job.input.lastPathComponent)\n  \(ffmpeg) \(args.joined(separator: " "))")

        let total = duration ?? 0
        let result = await runner.run(ffmpeg: ffmpeg, args: args) { [weak job] seconds in
            guard total > 0 else { return }
            Task { @MainActor in job?.progress = min(seconds / total, 0.99) }
        }
        Log.write(
            "END \(job.input.lastPathComponent) status=\(result.status) cancelled=\(result.wasCancelled)"
                + (result.errorText.isEmpty ? "" : "\n\(result.errorText)"))

        if result.wasCancelled {
            try? FileManager.default.removeItem(at: out)
            job.state = .cancelled
        } else if result.status == 0 {
            job.progress = 1
            job.output = out
            job.state = .done
        } else {
            try? FileManager.default.removeItem(at: out)
            let lines = result.errorText
                .split(whereSeparator: \.isNewline)
                .suffix(3)
                .joined(separator: "\n")
            job.state = .failed(lines.isEmpty ? "ffmpeg exited with code \(result.status)." : lines)
        }
    }

    static func outputURL(for input: URL, format: OutputFormat, folder: URL?, overwrite: Bool)
        -> URL
    {
        let dir = folder ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(format.ext)

        // Never write over the source file.
        if candidate.standardizedFileURL == input.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(base) (converted)").appendingPathExtension(
                format.ext)
        }
        if !overwrite {
            var n = 1
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = dir.appendingPathComponent("\(base) (\(n))").appendingPathExtension(
                    format.ext)
                n += 1
            }
        }
        return candidate
    }
}
