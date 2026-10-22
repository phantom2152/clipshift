import Foundation

enum FFmpeg {
    /// `ffmpeg -i file` prints "Duration: HH:MM:SS.xx" on stderr; no ffprobe needed.
    static func probeDuration(ffmpeg: String, input: URL) async -> Double? {
        guard
            let text = await ProcessRunner.capture(
                ffmpeg, ["-hide_banner", "-nostdin", "-i", input.path], stream: .stderr),
            let r = text.range(
                of: #"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression)
        else { return nil }

        let parts = text[r].dropFirst("Duration: ".count).split(separator: ":")
        guard parts.count == 3,
            let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }
}
