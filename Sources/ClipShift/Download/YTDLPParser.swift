import Foundation

enum YTDLPEvent: Sendable {
    case download(
        fraction: Double?, speed: Double?, eta: Double?,
        index: Int?, count: Int?, playlist: String?, title: String?)
    case stage(String)
    /// yt-dlp printed the final path of one finished item.
    case fileFinished
}

/// Turns yt-dlp's stdout lines into events and collects the final file paths.
/// Safe to call from the process's reader threads.
final class YTDLPOutputParser: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    /// True for video downloads: yt-dlp fetches the video stream and then the audio stream,
    /// each counting 0→100%. They are folded into one bar.
    private let splitStreams: Bool

    init(splitStreams: Bool) { self.splitStreams = splitStreams }

    /// Final file paths printed by `--print after_move:filepath`.
    var outputs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func parse(_ line: String) -> YTDLPEvent? {
        if line.hasPrefix("DL|") { return parseProgress(line) }

        if line.hasPrefix("PP|") {
            // PP|started|FFmpegExtractAudio
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if p.count >= 3, p[1] == "started" { return .stage(Self.stageName(p[2])) }
            return nil
        }

        // Anything else on stdout is a final file path from --print.
        lock.lock()
        paths.append(line)
        lock.unlock()
        return .fileFinished
    }

    private func parseProgress(_ line: String) -> YTDLPEvent? {
        // DL|downloaded|total|estimate|speed|eta|index|count|vcodec|acodec|playlist␟title
        let p = line.split(separator: "|", maxSplits: 10, omittingEmptySubsequences: false)
            .map(String.init)
        guard p.count >= 11 else { return nil }

        var fraction: Double? = nil
        let total = Double(p[2]) ?? Double(p[3])
        if let dl = Double(p[1]), let t = total, t > 0 { fraction = min(max(dl / t, 0), 1) }
        fraction = combined(fraction, vcodec: p[8], acodec: p[9])

        let names = p[10].split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        func clean(_ s: String?) -> String? {
            guard let s, !s.isEmpty, s != "NA" else { return nil }
            return s
        }
        return .download(
            fraction: fraction, speed: Double(p[4]), eta: Double(p[5]),
            index: Int(p[6]), count: Int(p[7]),
            playlist: clean(names.count > 1 ? names[0] : nil),
            title: clean(names.last))
    }

    /// Maps the video stream to 0–85% and the audio stream to 85–100%.
    /// A single combined stream, or unknown codecs, pass through unchanged.
    private func combined(_ f: Double?, vcodec: String, acodec: String) -> Double? {
        guard splitStreams, let f else { return f }
        func has(_ c: String) -> Bool? { c.isEmpty || c == "NA" ? nil : c != "none" }
        guard let v = has(vcodec), let a = has(acodec) else { return f }
        if v && !a { return f * 0.85 }
        if a && !v { return 0.85 + f * 0.15 }
        return f
    }

    private static func stageName(_ pp: String) -> String {
        if pp.contains("ExtractAudio") { return "Extracting audio…" }
        if pp.contains("Merger") { return "Merging video and audio…" }
        if pp.contains("Convertor") { return "Converting cover art…" }
        if pp.contains("EmbedThumbnail") { return "Embedding cover art…" }
        if pp.contains("Metadata") { return "Writing tags…" }
        return "Processing…"
    }
}
