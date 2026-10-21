import Foundation

enum YTDLPEvent: Sendable {
    case download(
        fraction: Double?, speed: Double?, eta: Double?,
        index: Int?, count: Int?, title: String?)
    case stage(String)
}

struct YTDLPResult: Sendable {
    var status: Int32
    var wasCancelled: Bool
    var errorText: String
    var outputs: [String]
}

/// Runs one yt-dlp process. Thread-safe so cancel() can be called from the UI.
final class YTDLPRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var stderrTail = ""
    private var outputs: [String] = []
    private let splitter = LineSplitter()

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
        p.interrupt()  // SIGINT lets yt-dlp stop cleanly
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning { p.terminate() }
        }
    }

    private func appendErr(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock()
        stderrTail += String(decoding: d, as: UTF8.self)
        if stderrTail.count > 4000 { stderrTail = String(stderrTail.suffix(4000)) }
        lock.unlock()
    }

    private func currentErr() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrTail
    }

    private static func stageName(_ pp: String) -> String {
        if pp.contains("ExtractAudio") { return "Extracting audio…" }
        if pp.contains("Merger") { return "Merging video and audio…" }
        if pp.contains("Convertor") { return "Converting cover art…" }
        if pp.contains("EmbedThumbnail") { return "Embedding cover art…" }
        if pp.contains("Metadata") { return "Writing tags…" }
        return "Processing…"
    }

    private func handleOut(_ d: Data, _ onEvent: @Sendable (YTDLPEvent) -> Void) {
        guard !d.isEmpty else { return }
        lock.lock()
        let lines = splitter.feed(d)
        lock.unlock()

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("DL|") {
                // DL|downloaded|total|estimate|speed|eta|index|count|title
                let p = line.split(separator: "|", maxSplits: 8, omittingEmptySubsequences: false)
                    .map(String.init)
                guard p.count >= 9 else { continue }
                let downloaded = Double(p[1])
                let total = Double(p[2]) ?? Double(p[3])
                var fraction: Double? = nil
                if let dl = downloaded, let t = total, t > 0 { fraction = min(max(dl / t, 0), 1) }
                let title = (p[8] == "NA" || p[8].isEmpty) ? nil : p[8]
                onEvent(
                    .download(
                        fraction: fraction, speed: Double(p[4]), eta: Double(p[5]),
                        index: Int(p[6]), count: Int(p[7]), title: title))
            } else if line.hasPrefix("PP|") {
                // PP|started|FFmpegExtractAudio
                let p = line.split(separator: "|", omittingEmptySubsequences: false).map(
                    String.init)
                if p.count >= 3, p[1] == "started" { onEvent(.stage(Self.stageName(p[2]))) }
            } else {
                // Anything else on stdout is a final file path from --print.
                lock.lock()
                outputs.append(line)
                lock.unlock()
            }
        }
    }

    /// `extraPath` directories are added to PATH, because GUI apps start with a minimal one
    /// and yt-dlp may need to find helpers (ffmpeg, a JavaScript runtime) next to itself.
    func run(
        ytdlp: String, args: [String], extraPath: [String],
        onEvent: @escaping @Sendable (YTDLPEvent) -> Void
    ) async -> YTDLPResult {
        await withCheckedContinuation { (cont: CheckedContinuation<YTDLPResult, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ytdlp)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (extraPath + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
            p.environment = env

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
                handleOut(d, onEvent)
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
                // The final file path arrives right before exit, so drain what is left.
                handleOut(outPipe.fileHandleForReading.readDataToEndOfFile(), onEvent)
                appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                lock.lock()
                let outs = outputs
                lock.unlock()
                cont.resume(
                    returning: YTDLPResult(
                        status: proc.terminationStatus,
                        wasCancelled: isCancelled,
                        errorText: currentErr(),
                        outputs: outs))
            }

            lock.lock()
            if cancelled {
                lock.unlock()
                cont.resume(
                    returning: YTDLPResult(
                        status: -1, wasCancelled: true,
                        errorText: "", outputs: []))
                return
            }
            process = p
            lock.unlock()

            do {
                try p.run()
            } catch {
                cont.resume(
                    returning: YTDLPResult(
                        status: -1, wasCancelled: false,
                        errorText: error.localizedDescription, outputs: []))
            }
        }
    }
}

/// Builds the yt-dlp command line from Settings.
@MainActor
enum YTDLPCommand {
    static let downloadTemplate =
        "download:DL|%(progress.downloaded_bytes)s|%(progress.total_bytes)s"
        + "|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"
        + "|%(info.playlist_index)s|%(info.n_entries)s|%(info.title)s"
    static let postTemplate =
        "postprocess:PP|%(progress.status)s|%(progress.postprocessor)s"

    static func arguments(url: String) -> [String] {
        let s = Settings.shared
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

        var a: [String] = [
            "--newline", "--no-simulate", "--progress",
            "--print", "after_move:filepath",
            "--progress-template", downloadTemplate,
            "--progress-template", postTemplate,
            "--ffmpeg-location", s.resolvedFFmpegPath,
            "-P", s.resolvedDownloadFolder.path,
        ]

        var template = s.downloadFilenameTemplate.trimmingCharacters(in: .whitespaces)
        if template.isEmpty { template = Factory.downloadFilenameTemplate }

        if s.downloadPlaylists {
            a += ["--yes-playlist", "--playlist-end", String(max(1, s.downloadMaxPlaylistItems))]
            if s.downloadGroupPlaylists && isPlaylistURL(url) {
                template = s.downloadPlaylistPrefix + template
            }
        } else {
            a += ["--no-playlist"]
        }
        a += ["-o", template]

        if s.downloadAudioOnly {
            let fmt = s.downloadAudioFormat
            a += ["-f", "bestaudio/best", "-x", "--audio-format", fmt]
            if fmt != "best" {
                a += ["--audio-quality", String(clamp(s.downloadAudioQuality, 0, 10))]
            }
            if s.downloadEmbedCoverArt && fmt != "wav" {
                a += ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
            }
        } else {
            let h = s.downloadMaxHeight
            let selector = h > 0 ? "bv*[height<=\(h)]+ba/b[height<=\(h)]" : "bv*+ba/b"
            a += ["-f", selector, "--merge-output-format", s.downloadVideoContainer]
        }

        if s.downloadEmbedMetadata { a += ["--embed-metadata"] }
        a += splitArgs(s.downloadExtraArgs)
        a += ["--", url]
        return a
    }

    /// Splits on spaces, honoring single and double quotes.
    nonisolated static func splitArgs(_ text: String) -> [String] {
        var args: [String] = []
        var cur = ""
        var quote: Character? = nil
        var has = false
        for ch in text {
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                has = true
            } else if ch.isWhitespace {
                if has {
                    args.append(cur)
                    cur = ""
                    has = false
                }
            } else {
                cur.append(ch)
                has = true
            }
        }
        if has { args.append(cur) }
        return args
    }
    /// Playlist-like links: a list= parameter, or playlist/album/channel pages.
    nonisolated static func isPlaylistURL(_ url: String) -> Bool {
        guard let c = URLComponents(string: url) else { return false }
        if c.queryItems?.contains(where: { $0.name == "list" }) == true { return true }
        let path = c.path.lowercased()
        return ["/playlist", "/album", "/channel/", "/user/", "/c/", "/@"]
            .contains { path.contains($0) }
    }
}
