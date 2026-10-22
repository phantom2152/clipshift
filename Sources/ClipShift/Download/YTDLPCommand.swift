import Foundation

/// Builds the yt-dlp command line from the settings.
@MainActor
enum YTDLPCommand {
    static let downloadTemplate =
        "download:DL|%(progress.downloaded_bytes)s|%(progress.total_bytes)s"
        + "|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"
        + "|%(info.playlist_index)s|%(info.n_entries)s"
        + "|%(info.vcodec)s|%(info.acodec)s"
        + "|%(info.playlist_title)s\u{1F}%(info.title)s"
    static let postTemplate =
        "postprocess:PP|%(progress.status)s|%(progress.postprocessor)s"

    static func arguments(url: String) -> [String] {
        let s = AppSettings.shared
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }

        var a: [String] = [
            "--newline", "--no-simulate", "--progress",
            // Fewer progress lines, so the UI isn't redrawn dozens of times a second.
            "--progress-delta", "0.5",
            "--print", "after_move:filepath",
            "--progress-template", downloadTemplate,
            "--progress-template", postTemplate,
            "--ffmpeg-location", s.resolvedFFmpegPath,
            "-P", s.resolvedDownloadFolder.path,
        ]

        var template = s.downloadFilenameTemplate.trimmingCharacters(in: .whitespaces)
        if template.isEmpty { template = AppDefaults.filenameTemplate }

        if s.downloadPlaylists {
            a += ["--yes-playlist", "--playlist-end", String(max(1, s.downloadMaxPlaylistItems))]
            if s.downloadGroupPlaylists && isPlaylistURL(url) {
                template = s.downloadPlaylistPrefix + template
            }
        } else {
            // --no-playlist only affects links that point at a video inside a list.
            // A pure playlist link needs the item limit as well, or it would download everything.
            a += ["--no-playlist", "--playlist-items", "1"]
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
