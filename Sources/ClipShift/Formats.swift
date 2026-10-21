import Foundation

enum Quality: String, CaseIterable, Identifiable {
    case high, medium, small
    var id: String { rawValue }
    var label: String {
        switch self {
        case .high: return "High quality"
        case .medium: return "Balanced"
        case .small: return "Small file"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4, hevc, mov, mkv, webm, gif, mp3, m4a, wav, remux
    var id: String { rawValue }

    var label: String {
        switch self {
        case .mp4: return "MP4 · H.264"
        case .hevc: return "MP4 · H.265 (hardware)"
        case .mov: return "MOV · H.264"
        case .mkv: return "MKV · H.264"
        case .webm: return "WebM · VP9"
        case .gif: return "GIF"
        case .mp3: return "MP3 (audio only)"
        case .m4a: return "M4A · AAC (audio only)"
        case .wav: return "WAV (audio only)"
        case .remux: return "Remux to MKV (no re-encode)"
        }
    }

    var ext: String {
        switch self {
        case .mp4, .hevc: return "mp4"
        case .mov: return "mov"
        case .mkv, .remux: return "mkv"
        case .webm: return "webm"
        case .gif: return "gif"
        case .mp3: return "mp3"
        case .m4a: return "m4a"
        case .wav: return "wav"
        }
    }

    var usesQuality: Bool {
        switch self {
        case .wav, .remux: return false
        default: return true
        }
    }

    /// Output-side ffmpeg arguments (everything between `-i input` and the output path).
    func arguments(quality q: Quality) -> [String] {
        func pick<T>(_ high: T, _ medium: T, _ small: T) -> T {
            switch q {
            case .high: return high
            case .medium: return medium
            case .small: return small
            }
        }
        let maps = ["-map", "0:V:0?", "-map", "0:a:0?"]

        switch self {
        case .mp4, .mov, .mkv:
            var a =
                maps + [
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                    "-c:v", "libx264", "-preset", "medium",
                    "-crf", pick("18", "23", "28"),
                    "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k",
                ]
            if self != .mkv { a += ["-movflags", "+faststart"] }
            return a

        case .hevc:
            return maps + [
                "-c:v", "hevc_videotoolbox",
                "-q:v", pick("65", "50", "35"),
                "-tag:v", "hvc1",
                "-c:a", "aac", "-b:a", "192k",
                "-movflags", "+faststart",
            ]

        case .webm:
            return maps + [
                "-c:v", "libvpx-vp9", "-b:v", "0",
                "-crf", pick("24", "31", "38"),
                "-row-mt", "1", "-cpu-used", "4",
                "-c:a", "libopus", "-b:a", "128k",
            ]

        case .gif:
            let width: Int = pick(960, 640, 480)
            let fps: Int = pick(15, 12, 10)
            let filter =
                "fps=\(fps),scale='min(\(width),iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
            return ["-map", "0:V:0", "-vf", filter, "-loop", "0"]

        case .mp3:
            return ["-vn", "-c:a", "libmp3lame", "-q:a", pick("0", "2", "5")]

        case .m4a:
            return ["-vn", "-c:a", "aac", "-b:a", pick("256k", "192k", "128k")]

        case .wav:
            return ["-vn", "-c:a", "pcm_s16le"]

        case .remux:
            return ["-map", "0", "-c", "copy", "-ignore_unknown"]
        }
    }
}
