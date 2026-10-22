import AppKit

@MainActor
final class Job: ObservableObject, Identifiable {
    enum State: Equatable {
        case waiting, running, done
        case failed(String)
        case cancelled

        var canRetry: Bool {
            switch self {
            case .failed, .cancelled: return true
            default: return false
            }
        }

        var phase: JobPhase {
            switch self {
            case .waiting: return .waiting
            case .running: return .active
            case .done: return .done
            case .failed: return .failed
            case .cancelled: return .cancelled
            }
        }
    }

    let id = UUID()
    let input: URL
    var runner = ProcessRunner()
    var deleteInputOnSuccess = false
    @Published var state: State = .waiting
    @Published var progress: Double = 0
    @Published var indeterminate = false
    @Published var output: URL?
    var duration: Double = 0
    @Published var speed: Double?
    @Published var outputSize: Int64?
    let fileSize: Int64?

    init(input: URL) {
        self.input = input
        self.fileSize = (try? input.resourceValues(forKeys: [.fileSizeKey]))?
            .fileSize.map(Int64.init)
    }
}

@MainActor
final class ConversionManager: ObservableObject {
    static let shared = ConversionManager()

    @Published var jobs: [Job] = []
    @Published var isRunning = false

    /// The single owner of the main window's pickers. Downloads read these too, so
    /// "convert after download" uses the same choice.
    @Published var format: OutputFormat
    @Published var quality: Quality

    private var cancelRequested = false
    private var batchDone = 0
    private let sleepGuard = SleepGuard()

    private init() {
        let s = AppSettings.shared
        format = s.rememberLastUsed ? (s.lastFormat ?? s.defaultFormat) : s.defaultFormat
        quality = s.rememberLastUsed ? (s.lastQuality ?? s.defaultQuality) : s.defaultQuality
    }

    var hasPending: Bool { jobs.contains { $0.state == .waiting || $0.state.canRetry } }

    // MARK: Adding and removing

    /// Adds finished downloads without the file-type filter or notices.
    func addDownloaded(_ urls: [URL], deleteOriginal: Bool) {
        for url in urls where !jobs.contains(where: { $0.input.path == url.path }) {
            let job = Job(input: url)
            job.deleteInputOnSuccess = deleteOriginal
            jobs.append(job)
        }
    }

    /// Adds files and folders. Folders are scanned off the main thread.
    func add(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        let limits = MediaFilter.currentLimits()

        Task {
            let found = await Task.detached(priority: .userInitiated) {
                MediaFilter.classify(fileURLs, limits: limits)
            }.value

            for url in found.files where !jobs.contains(where: { $0.input.path == url.path }) {
                jobs.append(Job(input: url))
            }

            var notes: [String] = []
            if !found.rejectedFolders.isEmpty {
                notes.append(
                    "Too many files in: \(found.rejectedFolders.joined(separator: ", ")). "
                        + "Folders are limited to \(limits.maxFiles) media files, so nothing from them was added."
                )
            }
            if found.skippedFiles > 0 {
                notes.append(
                    "Skipped \(Fmt.count(found.skippedFiles, "file")) that aren't video or audio.")
            }
            if !notes.isEmpty { NoticeCenter.shared.post(notes.joined(separator: "\n")) }
        }
    }

    func remove(ids: Set<UUID>) {
        jobs.removeAll { ids.contains($0.id) && $0.state != .running }
    }

    func clearFinished() {
        jobs.removeAll { $0.state == .done }
    }

    /// Removes everything except a job that is currently running.
    func clearAll() {
        jobs.removeAll { $0.state != .running }
    }

    func cancelAll() {
        cancelRequested = true
        for job in jobs where job.state == .running { job.runner.cancel() }
    }

    // MARK: Running

    func start(retryFailed: Bool = true) {
        guard !isRunning else { return }
        if retryFailed {
            for job in jobs where job.state.canRetry { job.state = .waiting }
        }
        isRunning = true
        cancelRequested = false
        batchDone = 0

        let format = self.format
        let quality = self.quality
        let s = AppSettings.shared
        if s.rememberLastUsed { s.saveLast(format: format, quality: quality) }
        if s.preventSleep { sleepGuard.begin("Converting media") }
        if s.notifyWhenDone { Notifier.requestAuthorization() }

        Task {
            var finished: [URL] = []
            var failed = 0
            while !cancelRequested, let job = jobs.first(where: { $0.state == .waiting }) {
                await convert(job, format: format, quality: quality)
                if job.state == .done, let out = job.output {
                    finished.append(out)
                    batchDone += 1
                }
                if case .failed = job.state { failed += 1 }
                updateDock()
            }
            isRunning = false
            sleepGuard.end()
            NSApp.dockTile.badgeLabel = nil
            WorkFinished.announce(finished: finished, failed: failed, verb: "converted")
        }
    }

    private func convert(_ job: Job, format: OutputFormat, quality: Quality) async {
        let s = AppSettings.shared
        let ffmpeg = s.resolvedFFmpegPath
        guard FileManager.default.isExecutableFile(atPath: ffmpeg) else {
            Log.write("ERROR ffmpeg not found at \(ffmpeg)")
            job.state = .failed(
                "ffmpeg not found at \(ffmpeg). Set the correct path in Settings (⌘,) → Tools.")
            return
        }

        let runner = ProcessRunner()
        job.runner = runner
        job.progress = 0
        job.state = .running

        let out = Self.outputURL(
            for: job.input, format: format,
            folder: s.outputFolder, overwrite: s.overwriteExisting)
        if let folder = s.outputFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let duration = await FFmpeg.probeDuration(ffmpeg: ffmpeg, input: job.input)
        job.indeterminate = (duration ?? 0) <= 0
        if runner.isCancelled {
            job.state = .cancelled
            return
        }

        let hwIn = s.hardwareDecode ? ["-hwaccel", "videotoolbox"] : []
        let args =
            ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"] + hwIn
            + ["-i", job.input.path, "-progress", "pipe:1", "-nostats"]
            + format.arguments(quality: quality) + [out.path]

        Log.write(
            "START \(job.input.lastPathComponent)\n  \(ffmpeg) \(args.joined(separator: " "))")

        let total = duration ?? 0
        job.duration = total
        job.speed = nil
        let result = await runner.run(executable: ffmpeg, arguments: args) {
            [weak job, weak self] line in
            if line.hasPrefix("out_time_us=") {
                guard total > 0, let us = Double(line.dropFirst("out_time_us=".count)) else {
                    return
                }
                Task { @MainActor in
                    job?.progress = min(us / 1_000_000 / total, 0.99)
                    self?.updateDock()
                }
            } else if line.hasPrefix("speed=") {
                let v = line.dropFirst("speed=".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "x "))
                guard let sp = Double(v), sp > 0 else { return }
                Task { @MainActor in
                    guard let job else { return }
                    // Smooth it, since ffmpeg's reported speed jitters.
                    job.speed = job.speed.map { $0 * 0.7 + sp * 0.3 } ?? sp
                }
            }
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
            job.outputSize = (try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(
                Int64.init)
            job.state = .done
            if job.deleteInputOnSuccess, out.standardizedFileURL != job.input.standardizedFileURL {
                try? FileManager.default.trashItem(at: job.input, resultingItemURL: nil)
                Log.write("TRASHED original \(job.input.path)")
            }
        } else {
            try? FileManager.default.removeItem(at: out)
            let lines = result.errorText
                .split(whereSeparator: \.isNewline)
                .suffix(3)
                .joined(separator: "\n")
            job.state = .failed(lines.isEmpty ? "ffmpeg exited with code \(result.status)." : lines)
        }
    }

    func updateDock() {
        guard AppSettings.shared.showDockProgress, isRunning else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let running = jobs.first { $0.state == .running }
        let waiting = jobs.filter { $0.state == .waiting }.count
        let total = batchDone + (running == nil ? 0 : 1) + waiting
        guard total > 0 else { return }
        let value = (Double(batchDone) + (running?.progress ?? 0)) / Double(total)
        NSApp.dockTile.badgeLabel = "\(Int(value * 100))%"
    }

    // MARK: Output naming

    static func outputURL(for input: URL, format: OutputFormat, folder: URL?, overwrite: Bool)
        -> URL
    {
        let s = AppSettings.shared
        let dir = folder ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(format.ext)

        // An empty suffix would still point at the source, so fall back to the factory one.
        var convertedSuffix = s.convertedSuffix
        if convertedSuffix.trimmingCharacters(in: .whitespaces).isEmpty {
            convertedSuffix = AppDefaults.convertedSuffix
        }

        // Never write over the source file.
        if candidate.standardizedFileURL == input.standardizedFileURL {
            candidate = dir.appendingPathComponent("\(base)\(convertedSuffix)")
                .appendingPathExtension(format.ext)
        }
        if !overwrite {
            var n = 1
            while FileManager.default.fileExists(atPath: candidate.path) {
                // Without a "#" in the pattern, the number is appended so the loop always advances.
                let tag =
                    s.duplicateFormat.contains("#")
                    ? s.duplicateFormat.replacingOccurrences(of: "#", with: String(n))
                    : "\(s.duplicateFormat)\(n)"
                candidate = dir.appendingPathComponent("\(base)\(tag)").appendingPathExtension(
                    format.ext)
                n += 1
            }
        }
        return candidate
    }
}
