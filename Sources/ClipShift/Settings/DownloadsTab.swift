import SwiftUI

struct DownloadsTab: View {
    @ObservedObject private var s = AppSettings.shared

    private static let audioFormats = ["mp3", "m4a", "opus", "flac", "wav", "best"]
    private static let containers = ["mp4", "mkv", "webm"]

    private static let heights: [IntChoiceRow.Choice] = [
        .init(value: 0, label: "Best available"),
        .init(value: 2160, label: "2160p (4K)"),
        .init(value: 1440, label: "1440p"),
        .init(value: 1080, label: "1080p"),
        .init(value: 720, label: "720p"),
        .init(value: 480, label: "480p"),
        .init(value: 360, label: "360p"),
    ]

    private static let audioQualities: [IntChoiceRow.Choice] = (0...10).map {
        .init(
            value: $0,
            label: $0 == 0 ? "0 · Best" : $0 == 10 ? "10 · Smallest" : "\($0)")
    }

    var body: some View {
        Form {
            Section("Save to") {
                FolderRow(
                    emptyLabel: "Downloads folder", resetTitle: "Reset",
                    path: $s.downloadFolderPath)
                TextField("File name template", text: $s.downloadFilenameTemplate)
                    .font(.system(.body, design: .monospaced))
                Hint(
                    "yt-dlp output template. %(title)s is the video title, %(uploader)s the channel, %(id)s the video id."
                )
            }

            Section("Audio downloads") {
                Hint("Used when \"Audio only\" is ticked next to the link box on the main screen.")
                Picker("Audio format", selection: $s.downloadAudioFormat) {
                    ForEach(Self.audioFormats, id: \.self) { Text($0).tag($0) }
                }
                IntChoiceRow(
                    title: "Audio quality", choices: Self.audioQualities,
                    value: $s.downloadAudioQuality
                )
                .disabled(s.downloadAudioFormat == "best")
                Toggle("Embed cover art", isOn: $s.downloadEmbedCoverArt)
                Hint(
                    "Quality 0 is best, 10 is smallest (MP3 and similar). \"best\" keeps the original audio without re-encoding."
                )
            }

            Section("Video downloads") {
                Picker("Video container", selection: $s.downloadVideoContainer) {
                    ForEach(Self.containers, id: \.self) { Text($0).tag($0) }
                }
                IntChoiceRow(
                    title: "Max resolution", choices: Self.heights, value: $s.downloadMaxHeight)
            }

            Section("Playlists") {
                Toggle("Download whole playlists", isOn: $s.downloadPlaylists)
                IntRow(title: "Max items per playlist", value: $s.downloadMaxPlaylistItems)
                    .disabled(!s.downloadPlaylists)
                Toggle("Group playlist downloads into a folder", isOn: $s.downloadGroupPlaylists)
                    .disabled(!s.downloadPlaylists)
                TextField("Folder and numbering prefix", text: $s.downloadPlaylistPrefix)
                    .font(.system(.body, design: .monospaced))
                    .disabled(!s.downloadPlaylists || !s.downloadGroupPlaylists)
                Hint(
                    "When off, a playlist link downloads only its first video, and a video link inside a playlist downloads only that video. The prefix goes in front of the file name template and is empty for single videos."
                )
            }

            Section("Convert after download") {
                Toggle(
                    "Move the downloaded original to the Trash after converting",
                    isOn: $s.deleteOriginalAfterConvert)
                Hint(
                    "The \"Convert after download\" checkbox is on the main screen and starts off every time. It uses the Format and Quality shown there when you start the download, plus your Convert settings. If the output folder is \"same as source\", converted files stay next to the download."
                )
            }

            Section("Extras") {
                Toggle(
                    "Embed metadata (title, artist, album, year…)", isOn: $s.downloadEmbedMetadata)
                TextField("Extra yt-dlp arguments", text: $s.downloadExtraArgs, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                Hint(
                    "Advanced. Added to every download, for example: --cookies-from-browser safari"
                )
            }

            ResetSection { s.reset(.downloads) }
        }
        .formStyle(.grouped)
    }
}
