import AppKit

@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case waiting, downloading, processing, done
        case failed(String)
        case cancelled

        var isBusy: Bool { self == .downloading || self == .processing }
        var canRetry: Bool {
            switch self {
            case .failed, .cancelled: return true
            default: return false
            }
        }
    }

    let id = UUID()
    let url: String
    var runner = YTDLPRunner()
    @Published var state: State = .waiting
    @Published var progress = 0.0
    @Published var indeterminate = true
    @Published var speed: Double?
    @Published var eta: Double?
    @Published var title: String?
    @Published var itemText: String?
    @Published var stage = ""
    @Published var outputs: [URL] = []
    @Published var note: String?

    struct Track: Identifiable, Equatable {
        enum State: Equatable { case downloading, processing, done, failed, cancelled }
        let id: Int  // position in the playlist
        var title: String
        var state: State = .downloading
        var progress = 0.0
        var stage = ""
        var known = false  // true once yt-dlp has reported a real percentage
    }

    enum CloseReason { case nextStarted, succeeded, cancelled, failed }

    @Published var playlistTitle: String?
    @Published var playlistCount: Int?
    @Published var tracks: [Track] = []
    @Published var expanded = false

    var isPlaylist: Bool { (playlistCount ?? 0) > 1 }
    var doneCount: Int { tracks.filter { $0.state == .done }.count }

    /// Whole-playlist progress: finished songs plus the fraction of the current one.
    var overall: Double {
        guard let n = playlistCount, n > 0 else { return progress }
        let current =
            tracks.last(where: { $0.state == .downloading || $0.state == .processing })?.progress
            ?? 0
        return min((Double(doneCount) + current) / Double(n), 1)
    }

    func updateTrack(index: Int, title: String?, fraction: Double?) {
        if let i = tracks.firstIndex(where: { $0.id == index }) {
            if let title { tracks[i].title = title }
            if tracks[i].state == .downloading, let f = fraction {
                tracks[i].progress = f
                tracks[i].known = true
            }
        } else {
            closeOpenTracks(.nextStarted)
            var t = Track(id: index, title: title ?? "Track \(index)")
            if let f = fraction {
                t.progress = f
                t.known = true
            }
            tracks.append(t)
        }
    }

    func markCurrentTrackProcessing(_ name: String) {
        guard let i = tracks.indices.last,
            tracks[i].state == .downloading || tracks[i].state == .processing
        else { return }
        tracks[i].state = .processing
        tracks[i].stage = name
        tracks[i].progress = 1
    }

    func closeOpenTracks(_ reason: CloseReason) {
        for i in tracks.indices
        where tracks[i].state == .downloading || tracks[i].state == .processing {
            let wasProcessing = tracks[i].state == .processing
            switch reason {
            case .cancelled: tracks[i].state = .cancelled
            case .failed: tracks[i].state = wasProcessing ? .done : .failed
            case .succeeded: tracks[i].state = .done
            case .nextStarted:
                // Moving on while the bar was clearly short of the end suggests it was skipped.
                let stoppedEarly = !wasProcessing && tracks[i].known && tracks[i].progress < 0.9
                tracks[i].state = stoppedEarly ? .failed : .done
            }
            if tracks[i].state == .done { tracks[i].progress = 1 }
        }
    }

    init(url: String) { self.url = url }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var jobs: [DownloadJob] = []
    @Published var isRunning = false
    private var cancelRequested = false
    private var sleepActivity: NSObjectProtocol?

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
            let alert = NSAlert()
            alert.messageText = "Some links weren't added"
            alert.informativeText =
                "\(rejected) item\(rejected == 1 ? "" : "s") didn't look like a web link (http or https)."
            alert.runModal()
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

    func start() {
        guard !isRunning, jobs.contains(where: { $0.state == .waiting }) else { return }
        isRunning = true
        cancelRequested = false

        let s = Settings.shared
        if s.preventSleep {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Downloading media")
        }
        if s.notifyWhenDone { Notifier.requestAuthorization() }

        Task {
            var finished: [URL] = []
            var failed = 0
            while !cancelRequested, let job = jobs.first(where: { $0.state == .waiting }) {
                await download(job)
                if job.state == .done { finished += job.outputs }
                if case .failed = job.state { failed += 1 }
            }
            isRunning = false
            if let a = sleepActivity {
                ProcessInfo.processInfo.endActivity(a)
                sleepActivity = nil
            }

            if !finished.isEmpty {
                if s.playSoundWhenDone { NSSound(named: NSSound.Name(s.soundName))?.play() }
                if s.revealWhenDone { NSWorkspace.shared.activateFileViewerSelecting(finished) }
            }
            if s.notifyWhenDone, !NSApp.isActive, !(finished.isEmpty && failed == 0) {
                var body = "\(finished.count) file\(finished.count == 1 ? "" : "s") downloaded"
                if failed > 0 { body += ", \(failed) failed" }
                Notifier.post(title: "ClipShift", body: body)
            }
        }
    }

    private func download(_ job: DownloadJob) async {
        let s = Settings.shared
        let ytdlp = s.resolvedYTDLPPath
        guard FileManager.default.isExecutableFile(atPath: ytdlp) else {
            Log.write("ERROR yt-dlp not found at \(ytdlp)")
            job.state = .failed(
                "yt-dlp not found at \(ytdlp). Set the correct path in Settings (⌘,) → Tools.")
            return
        }
        try? FileManager.default.createDirectory(
            at: s.resolvedDownloadFolder,
            withIntermediateDirectories: true)

        job.runner = YTDLPRunner()
        let runner = job.runner
        job.progress = 0
        job.indeterminate = true
        job.speed = nil
        job.eta = nil
        job.itemText = nil
        job.stage = ""
        job.note = nil
        job.outputs = []
        job.tracks = []
        job.playlistTitle = nil
        job.playlistCount = nil
        job.state = .downloading

        let args = YTDLPCommand.arguments(url: job.url)
        Log.write("START-DL \(job.url)\n  \(ytdlp) \(args.joined(separator: " "))")

        let extraPath = [ytdlp, s.resolvedFFmpegPath].map {
            ($0 as NSString).deletingLastPathComponent
        }
        let result = await runner.run(ytdlp: ytdlp, args: args, extraPath: extraPath) {
            [weak job] event in
            Task { @MainActor in
                guard let job else { return }
                Self.apply(event, to: job)
            }
        }

        let urls = result.outputs
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
            job.closeOpenTracks(result.status == 0 ? .succeeded : .nextStarted)
            job.progress = 1
            if result.status != 0 {
                job.note = Self.errorSummary(result.errorText, fallback: "Finished with errors.")
            }
            job.state = .done
        } else {
            job.closeOpenTracks(.failed)
            job.state = .failed(
                Self.errorSummary(
                    result.errorText,
                    fallback: "yt-dlp exited with code \(result.status)."))
        }
    }

    private static func apply(_ event: YTDLPEvent, to job: DownloadJob) {
        guard job.state.isBusy else { return }  // ignore late events after the job ended
        switch event {
        case .download(
            let fraction, let speed, let eta, let index, let count, let playlist, let title):
            if job.state != .downloading { job.state = .downloading }
            if let fraction {
                job.progress = fraction
                job.indeterminate = false
            } else {
                job.indeterminate = true
            }
            job.speed = speed
            job.eta = eta
            if let title { job.title = title }
            if let playlist { job.playlistTitle = playlist }
            if let index, let count, count > 1 {
                job.playlistCount = count
                job.itemText = "\(index)/\(count)"
                job.updateTrack(index: index, title: title, fraction: fraction)
            }
        case .stage(let name):
            job.state = .processing
            job.stage = name
            job.markCurrentTrackProcessing(name)
        }
    }

    private static func errorSummary(_ text: String, fallback: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let errors = lines.filter { $0.contains("ERROR") }
        let pick = errors.isEmpty ? Array(lines.suffix(3)) : Array(errors.suffix(2))
        let joined = pick.joined(separator: "\n")
        return joined.isEmpty ? fallback : joined
    }
}
