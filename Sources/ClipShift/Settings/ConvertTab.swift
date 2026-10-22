import SwiftUI

/// Everything about converting files: where they go, the quality presets, accepted input
/// and (collapsed) the rarely touched encoder details.
struct ConvertTab: View {
    @ObservedObject private var s = AppSettings.shared

    private static let presets = [
        "ultrafast", "superfast", "veryfast", "faster", "fast",
        "medium", "slow", "slower", "veryslow",
    ]

    var body: some View {
        Form {
            Section("Save to") {
                FolderRow(
                    emptyLabel: "Same folder as source", resetTitle: "Same as Source",
                    path: $s.outputFolderPath)
                Toggle("Overwrite existing files (otherwise keep both)", isOn: $s.overwriteExisting)
                TextField("Suffix if output would replace the source", text: $s.convertedSuffix)
            }

            Section("Video quality") {
                Picker("H.264 speed preset", selection: $s.x264Preset) {
                    ForEach(Self.presets, id: \.self) { Text($0).tag($0) }
                }
                TripleRow(title: "H.264 CRF", value: $s.crf)
                Hint("Lower CRF = better quality, bigger file. Typical range 17–28.")
                TripleRow(title: "H.265 quality", value: $s.hevcQuality)
                Hint("VideoToolbox quality, 1–100. Higher = better quality, bigger file.")
                TripleRow(title: "WebM (VP9) CRF", value: $s.vp9CRF)
                TripleRow(title: "GIF max width", unit: "px", value: $s.gifWidth)
                TripleRow(title: "GIF frame rate", unit: "fps", value: $s.gifFPS)
                Toggle(
                    "Use the Mac's hardware encoder for H.264 (MP4, MOV, MKV)",
                    isOn: $s.h264Hardware)
                Hint("Much faster and light on CPU, but files are larger at similar quality.")
            }

            Section("Audio quality") {
                TripleRow(title: "MP3 VBR quality", value: $s.mp3Quality)
                Hint("0–9. Lower = better quality, bigger file. 0 ≈ 245 kbps, 2 ≈ 190 kbps, 5 ≈ 130 kbps.")
                TripleRow(title: "M4A bitrate", unit: "kbps", value: $s.m4aBitrate)
            }

            Section("Input") {
                IntRow(title: "Max media files per folder", value: $s.maxFolderFiles)
                TextField("Extra file types", text: $s.extraExtensionsText, axis: .vertical)
                    .lineLimit(2...4)
                Hint(
                    "Extensions accepted in addition to what macOS recognizes as video or audio, separated by commas. A dropped folder over the file limit is rejected entirely."
                )
            }

            Section {
                DisclosureGroup("Advanced encoding") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use hardware decoding of the source", isOn: $s.hardwareDecode)
                        TripleRow(title: "Hardware H.264 quality", value: $s.h264HWQuality)
                            .disabled(!s.h264Hardware)
                        IntRow(title: "VP9 CPU used (0–8)", value: $s.vp9CPUUsed)
                        IntRow(title: "AAC bitrate (video)", unit: "kbps", value: $s.videoAACBitrate)
                        IntRow(title: "Opus bitrate (WebM)", unit: "kbps", value: $s.opusBitrate)
                        IntRow(title: "Max entries scanned per folder", value: $s.maxVisitedEntries)
                        TextField("Suffix for duplicates", text: $s.duplicateFormat)
                        Hint(
                            "In the duplicate suffix, # becomes 1, 2, 3… Example: \" (#)\" gives \"song (1).mp3\"."
                        )
                    }
                    .padding(.top, 6)
                }
            }

            ResetSection { s.reset(.convert) }
        }
        .formStyle(.grouped)
    }
}
