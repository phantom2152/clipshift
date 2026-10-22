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

    var isAudioOnly: Bool {
        switch self {
        case .mp3, .m4a, .wav: return true
        default: return false
        }
    }

    /// Output-side ffmpeg arguments (everything between `-i input` and the output path).
    /// Values come from Settings and are clamped to ranges ffmpeg accepts.
    @MainActor
    func arguments(quality q: Quality) -> [String] {
        let s = AppSettings.shared
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

        let maps = ["-map", "0:V:0?", "-map", "0:a:0?"]

        switch self {
        case .mp4, .mov, .mkv:
            let crf = String(clamp(s.crf[q], 0, 51))
            let aac = "\(clamp(s.videoAACBitrate, 32, 640))k"
            var a = maps
            a += ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
            if s.h264Hardware {
                a += [
                    "-c:v", "h264_videotoolbox", "-q:v", String(clamp(s.h264HWQuality[q], 1, 100)),
                ]
            } else {
                a += ["-c:v", "libx264", "-preset", s.x264Preset, "-crf", crf]
            }
            a += ["-pix_fmt", "yuv420p"]
            a += ["-c:a", "aac", "-b:a", aac]
            if self != .mkv { a += ["-movflags", "+faststart"] }
            return a

        case .hevc:
            let quality = String(clamp(s.hevcQuality[q], 1, 100))
            let aac = "\(clamp(s.videoAACBitrate, 32, 640))k"
            var a = maps
            a += ["-c:v", "hevc_videotoolbox", "-q:v", quality, "-tag:v", "hvc1"]
            a += ["-c:a", "aac", "-b:a", aac]
            a += ["-movflags", "+faststart"]
            return a

        case .webm:
            let crf = String(clamp(s.vp9CRF[q], 0, 63))
            let cpu = String(clamp(s.vp9CPUUsed, 0, 8))
            let opus = "\(clamp(s.opusBitrate, 6, 510))k"
            var a = maps
            a += ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", crf]
            a += ["-row-mt", "1", "-cpu-used", cpu]
            a += ["-c:a", "libopus", "-b:a", opus]
            return a

        case .gif:
            let width = clamp(s.gifWidth[q], 16, 7680)
            let fps = clamp(s.gifFPS[q], 1, 60)
            let filter =
                "fps=\(fps),scale='min(\(width),iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
            return ["-map", "0:V:0", "-vf", filter, "-loop", "0"]

        case .mp3:
            return ["-vn", "-c:a", "libmp3lame", "-q:a", String(clamp(s.mp3Quality[q], 0, 9))]

        case .m4a:
            return ["-vn", "-c:a", "aac", "-b:a", "\(clamp(s.m4aBitrate[q], 32, 640))k"]

        case .wav:
            return ["-vn", "-c:a", "pcm_s16le"]

        case .remux:
            return ["-map", "0", "-c", "copy", "-ignore_unknown"]
        }
    }
}
