import AppKit

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var jobs: [DownloadJob] = []
    @Published var isRunning = false
    private var cancelRequested = false
    private let sleepGuard = SleepGuard()

    private init() {}

    // MARK: Queue

    /// Returns how many links were valid (new or already queued).
    @discardableResult
    func addAndStart(_ text: String) -> Int {
        var valid = 0
        var rejected = 0
        for token in text.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            guard let u = URL(string: token), u.host != nil,
                let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else {
                rejected += 1
                continue
            }
            valid += 1
            let alreadyQueued = jobs.contains {
                $0.url == token && ($0.state == .waiting || $0.state.isBusy)
            }
            if !alreadyQueued { jobs.append(DownloadJob(url: token)) }
        }
        if rejected > 0 {
            NoticeCenter.shared.post(
                "\(Fmt.count(rejected, "item")) didn't look like a web link (http or https) and was skipped."
            )
        }
        start()
        return valid
    }

    func retry(_ job: DownloadJob) {
        guard job.state.canRetry else { return }
        job.state = .waiting
        start()
    }

    func remove(_ job: DownloadJob) {
        guard !job.state.isBusy else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() { jobs.removeAll { $0.state == .done } }
    func clearAll() { jobs.removeAll { !$0.state.isBusy } }

    func cancelAll() {
        cancelRequested = true
        for job in jobs {
            if job.state == .waiting { job.state = .cancelled }
            if job.state.isBusy { job.runner.cancel() }
        }
    }

    /// Stops one link. A running link ends as Cancelled and the queue moves on to the next.
    func cancel(_ job: DownloadJob) {
        switch job.state {
        case .waiting: job.state = .cancelled
        case .downloading, .processing: job.runner.cancel()
        default: break
        }
    }

    // MARK: Running

    func start() {
        guard !isRunning, jobs.contains(where: { $0.state == .waiting }) else { return }
        isRunning = true
        cancelRequested = false

        let s = AppSettings.shared
        if s.preventSleep { sleepGuard.begin("Downloading media") }
        if s.notifyWhenDone { Notifier.requestAuthorization() }

        Task {
            var finished: [URL] = []
            var failed = 0
            while !cancelRequested, let job = jobs.first(where: { $0.state == .waiting }) {
                await download(job)
                if job.state == .done {
                    finished += job.outputs
                    handOff(job)
                }
                if case .failed = job.state { failed += 1 }
            }
            isRunning = false
            sleepGuard.end()

            // With "convert after download" on, the conversion announces the result instead.
            if !s.downloadThenConvert {
                WorkFinished.announce(finished: finished, failed: failed, verb: "downloaded")
            }
        }
    }

    private func download(_ job: DownloadJob) async {
        let s = AppSettings.shared
        let ytdlp = s.resolvedYTDLPPath
        guard FileManager.default.isExecutableFile(atPath: ytdlp) else {
            Log.write("ERROR yt-dlp not found at \(ytdlp)")
            job.state = .failed(
                "yt-dlp not found at \(ytdlp). Set the correct path in Settings (⌘,) → Tools.")
            return
        }
        try? FileManager.default.createDirectory(
            at: s.resolvedDownloadFolder, withIntermediateDirectories: true)

        let runner = ProcessRunner(stderrLimit: 4000, gracefulCancel: true)
        job.runner = runner
        job.reset()
        job.audioOnly = s.downloadAudioOnly
        job.state = .downloading

        let parser = YTDLPOutputParser(splitStreams: !s.downloadAudioOnly)
        let args = YTDLPCommand.arguments(url: job.url)
        Log.write("START-DL \(job.url)\n  \(ytdlp) \(args.joined(separator: " "))")

        let extraPath = [ytdlp, s.resolvedFFmpegPath].map {
            ($0 as NSString).deletingLastPathComponent
        }
        let result = await runner.run(executable: ytdlp, arguments: args, extraPath: extraPath) {
            [weak job] line in
            guard let event = parser.parse(line) else { return }
            Task { @MainActor in
                guard let job else { return }
                Self.apply(event, to: job)
            }
        }

        // The parser collected paths synchronously, so the last one is already in.
        let urls = parser.outputs
            .filter { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        Log.write(
            "END-DL \(job.url) status=\(result.status) cancelled=\(result.wasCancelled) files=\(urls.count)"
                + (result.errorText.isEmpty ? "" : "\n\(result.errorText)"))

        job.speed = nil
        job.eta = nil
        job.outputs = urls
        if result.wasCancelled {
            job.closeOpenTracks(.cancelled)
            job.state = .cancelled
        } else if result.status == 0 || !urls.isEmpty {
            job.closeOpenTracks(result.status == 0 ? .succeeded : .failed)
            job.progress = 1
            if result.status != 0 {
                job.note = Self.errorSummary(result.errorText, fallback: "Finished with errors.")
            }
            job.state = .done
        } else {
            job.closeOpenTracks(.failed)
            job.state = .failed(
                Self.errorSummary(
                    result.errorText, fallback: "yt-dlp exited with code \(result.status)."))
        }
    }

    private static func apply(_ event: YTDLPEvent, to job: DownloadJob) {
        guard job.state.isBusy else { return }  // ignore late events after the job ended
        switch event {
        case .download(
            let fraction, let speed, let eta, let index, let count, let playlist, let title):
            if job.state != .downloading { job.state = .downloading }
            if let fraction {
                if job.progress != fraction { job.progress = fraction }
                if job.indeterminate { job.indeterminate = false }
            } else if !job.indeterminate {
                job.indeterminate = true
            }
            if job.speed != speed { job.speed = speed }
            if job.eta != eta { job.eta = eta }
            if let title, job.title != title { job.title = title }
            if let playlist, job.playlistTitle != playlist { job.playlistTitle = playlist }
            if let index, let count, count > 1 {
                if job.playlistCount != count { job.playlistCount = count }
                job.updateTrack(index: index, title: title, fraction: fraction)
            }
        case .stage(let name):
            job.state = .processing
            job.stage = name
            job.markCurrentTrackProcessing(name)
        case .fileFinished:
            job.currentTrackFinished()
        }
    }

    // MARK: Convert after download

    /// With "convert after download" on, finished files go straight to the convert list.
    private func handOff(_ job: DownloadJob) {
        let s = AppSettings.shared
        guard s.downloadThenConvert, !job.outputs.isEmpty else { return }
        let cm = ConversionManager.shared

        // Audio has no picture, so turning it into MP4, GIF and the like gives nothing useful.
        let audioFriendly: [OutputFormat] = [.mp3, .m4a, .wav, .remux]
        if job.audioOnly && !audioFriendly.contains(cm.format) {
            NoticeCenter.shared.post(
                "Audio download not converted: \(cm.format.label) needs video. Pick an audio format in the main window to convert audio."
            )
            return
        }

        cm.addDownloaded(job.outputs, deleteOriginal: s.deleteOriginalAfterConvert)
        cm.start(retryFailed: false)
    }

    private static func errorSummary(_ text: String, fallback: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let errors = lines.filter { $0.contains("ERROR") }
        let pick = errors.isEmpty ? Array(lines.suffix(3)) : Array(errors.suffix(2))
        let joined = pick.joined(separator: "\n")
        return joined.isEmpty ? fallback : joined
    }
}
