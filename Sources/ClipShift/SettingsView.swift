import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            OutputTab().tabItem { Label("Output", systemImage: "folder") }
            VideoTab().tabItem { Label("Video", systemImage: "film") }
            AudioTab().tabItem { Label("Audio", systemImage: "waveform") }
            InputTab().tabItem { Label("Input", systemImage: "tray.and.arrow.down") }
            ToolsTab().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            DownloadsTab().tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            AdvancedTab().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 700, height: 540)
    }
}

// MARK: - Reusable pieces

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

private struct ResetSection: View {
    var title = "Reset This Tab to Defaults"
    let action: () -> Void
    var body: some View {
        Section {
            HStack {
                Spacer()
                Button(title, action: action)
            }
        }
    }
}

private struct IntRow: View {
    let title: String
    var unit: String? = nil
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// High / Balanced / Small number fields in one row.
private struct TripleRow: View {
    let title: String
    var unit: String? = nil
    @Binding var value: PerQuality<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                field("High", $value.high)
                field("Balanced", $value.medium)
                field("Small", $value.small)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }

    private func field(_ label: String, _ binding: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: binding, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var s = Settings.shared

    private static let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Format", selection: $s.defaultFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Quality", selection: $s.defaultQuality) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Remember the last used format and quality", isOn: $s.rememberLastUsed)
                Hint(
                    "When on, the main window starts with what you last converted with. The defaults above are used on first launch, or when this is off."
                )
            }

            Section("When conversions finish") {
                Toggle("Show converted files in Finder", isOn: $s.revealWhenDone)
                Toggle("Play a sound", isOn: $s.playSoundWhenDone)
                HStack {
                    Picker("Sound", selection: $s.soundName) {
                        ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Preview") { NSSound(named: NSSound.Name(s.soundName))?.play() }
                }
                .disabled(!s.playSoundWhenDone)
                Toggle(
                    "Send a notification when ClipShift is in the background",
                    isOn: $s.notifyWhenDone)
            }

            Section("Window") {
                Toggle("Quit when the last window closes", isOn: $s.quitWhenLastWindowCloses)
            }

            Section("While converting") {
                Toggle("Keep the Mac awake", isOn: $s.preventSleep)
                Toggle("Show progress on the Dock icon", isOn: $s.showDockProgress)
                Toggle("Show speed and time left on rows", isOn: $s.showSpeedETA)
            }

            Section("File list") {
                Stepper(value: $s.clearAllConfirmThreshold, in: 0...10_000) {
                    Text("Confirm Clear All above \(s.clearAllConfirmThreshold) files")
                }
                Toggle("Show before/after file size on finished rows", isOn: $s.showSizeChange)
                Hint("Set to 0 to always ask.")
            }

            ResetSection { s.resetGeneral() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Output

private struct OutputTab: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section("Save to") {
                HStack {
                    Text(
                        s.outputFolderPath.isEmpty
                            ? "Same folder as source"
                            : (s.outputFolderPath as NSString).abbreviatingWithTildeInPath
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") {
                        if let url = Panels.pickFolder() { s.outputFolderPath = url.path }
                    }
                    if !s.outputFolderPath.isEmpty {
                        Button("Same as Source") { s.outputFolderPath = "" }
                    }
                }
            }

            Section("Existing files") {
                Toggle("Overwrite existing files (otherwise keep both)", isOn: $s.overwriteExisting)
            }

            Section("Naming") {
                TextField("Suffix if output would replace the source", text: $s.convertedSuffix)
                TextField("Suffix for duplicates", text: $s.duplicateFormat)
                Hint(
                    "In the duplicate suffix, # becomes 1, 2, 3… Example: \" (#)\" gives \"song (1).mp3\"."
                )
            }

            ResetSection { s.resetOutput() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Video

private struct VideoTab: View {
    @ObservedObject private var s = Settings.shared

    private static let presets = [
        "ultrafast", "superfast", "veryfast", "faster", "fast",
        "medium", "slow", "slower", "veryslow",
    ]

    var body: some View {
        Form {
            Section("Hardware acceleration") {
                Toggle(
                    "Use the Mac's hardware encoder for H.264 (MP4, MOV, MKV)",
                    isOn: $s.h264Hardware)
                TripleRow(title: "Hardware quality", value: $s.h264HWQuality)
                    .disabled(!s.h264Hardware)
                Toggle("Use hardware decoding of the source", isOn: $s.hardwareDecode)
                Hint(
                    "Hardware encoding is much faster and uses little CPU, but makes larger files than software at similar quality. Doesn't apply to WebM or GIF."
                )
            }

            Section("H.264 (MP4, MOV, MKV)") {
                Picker("Speed preset", selection: $s.x264Preset) {
                    ForEach(Self.presets, id: \.self) { Text($0).tag($0) }
                }
                TripleRow(title: "CRF", value: $s.crf)
                Hint("Lower CRF = better quality, bigger file. Typical range 17–28.")
            }

            Section("H.265 hardware") {
                TripleRow(title: "Quality", value: $s.hevcQuality)
                Hint("VideoToolbox quality, 1–100. Higher = better quality, bigger file.")
            }

            Section("WebM · VP9") {
                TripleRow(title: "CRF", value: $s.vp9CRF)
                IntRow(title: "CPU used", value: $s.vp9CPUUsed)
                Hint("CPU used 0–8: higher is faster but lower quality.")
            }

            Section("GIF") {
                TripleRow(title: "Max width", unit: "px", value: $s.gifWidth)
                TripleRow(title: "Frame rate", unit: "fps", value: $s.gifFPS)
            }

            Section("Audio inside video") {
                IntRow(title: "AAC bitrate", unit: "kbps", value: $s.videoAACBitrate)
                IntRow(title: "Opus bitrate (WebM)", unit: "kbps", value: $s.opusBitrate)
            }

            ResetSection { s.resetVideo() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio

private struct AudioTab: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section("MP3") {
                TripleRow(title: "VBR quality", value: $s.mp3Quality)
                Hint(
                    "0–9. Lower = better quality, bigger file. 0 ≈ 245 kbps, 2 ≈ 190 kbps, 5 ≈ 130 kbps."
                )
            }

            Section("M4A · AAC") {
                TripleRow(title: "Bitrate", unit: "kbps", value: $s.m4aBitrate)
            }

            ResetSection { s.resetAudio() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Input

private struct InputTab: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section("Folders") {
                IntRow(title: "Max media files per folder", value: $s.maxFolderFiles)
                IntRow(title: "Max entries scanned", value: $s.maxVisitedEntries)
                Hint("A dropped folder over either limit is rejected entirely.")
            }

            Section("Extra file types") {
                TextField("Extensions", text: $s.extraExtensionsText, axis: .vertical)
                    .lineLimit(2...4)
                Hint(
                    "Accepted in addition to what macOS recognizes as video or audio. Separate with commas."
                )
            }

            ResetSection { s.resetInput() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tools

private struct ToolsTab: View {
    @ObservedObject private var s = Settings.shared
    @StateObject private var model = SettingsModel()

    private var testResult: String? {
        get { model.testResult }
        nonmutating set { model.testResult = newValue }
    }

    private var ffmpegExists: Bool {
        FileManager.default.isExecutableFile(atPath: s.resolvedFFmpegPath)
    }

    private var ytdlpTestResult: String? {
        get { model.ytdlpTestResult }
        nonmutating set { model.ytdlpTestResult = newValue }
    }

    private var ytdlpExists: Bool {
        FileManager.default.isExecutableFile(atPath: s.resolvedYTDLPPath)
    }

    var body: some View {
        Form {
            Section("ffmpeg") {
                HStack {
                    TextField("Path", text: $s.ffmpegPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let url = Panels.pickExecutable() { s.ffmpegPath = url.path }
                    }
                }
                HStack {
                    if ffmpegExists {
                        Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not found or not executable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Auto-detect") {
                        s.ffmpegPath = Settings.detectFFmpeg()
                        testResult = nil
                    }
                    Button("Test") { testFFmpeg() }.disabled(!ffmpegExists)
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Hint("Auto-detect checks the Homebrew locations (Apple Silicon, then Intel).")
            }

            Section("yt-dlp") {
                HStack {
                    TextField("Path", text: $s.ytdlpPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let url = Panels.pickExecutable(
                            name: "yt-dlp", startingAt: s.resolvedYTDLPPath)
                        {
                            s.ytdlpPath = url.path
                        }
                    }
                }
                HStack {
                    if ytdlpExists {
                        Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not found or not executable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Auto-detect") {
                        s.ytdlpPath = Settings.detectYTDLP()
                        ytdlpTestResult = nil
                    }
                    Button("Test") { testYTDLP() }.disabled(!ytdlpExists)
                }
                if let ytdlpTestResult {
                    Text(ytdlpTestResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Hint(
                    "Install with: brew install yt-dlp. Sites change often, so run brew upgrade yt-dlp if downloads start failing."
                )
            }

            ResetSection(title: "Reset to Auto-detected") {
                s.resetTools()
                testResult = nil
                ytdlpTestResult = nil
            }
        }
        .formStyle(.grouped)
    }

    private func testFFmpeg() {
        let path = s.resolvedFFmpegPath
        testResult = "Running…"
        Task {
            let text = await Task.detached { () -> String in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = ["-version"]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return "Could not run: \(error.localizedDescription)" }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return String(decoding: data, as: UTF8.self)
                    .split(separator: "\n").first.map(String.init) ?? "No output from ffmpeg."
            }.value
            testResult = text
        }
    }

    private func testYTDLP() {
        let path = s.resolvedYTDLPPath
        ytdlpTestResult = "Running…"
        Task {
            let text = await Task.detached { () -> String in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = ["--version"]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return "Could not run: \(error.localizedDescription)" }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let v = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? "No output from yt-dlp." : "yt-dlp version \(v)"
            }.value
            ytdlpTestResult = text
        }
    }
}

// MARK: - Downloads

private struct DownloadsTab: View {
    @ObservedObject private var s = Settings.shared

    private static let audioFormats = ["mp3", "m4a", "opus", "flac", "wav", "best"]
    private static let containers = ["mp4", "mkv", "webm"]

    var body: some View {
        Form {
            Section("Save to") {
                HStack {
                    Text(
                        s.downloadFolderPath.isEmpty
                            ? "Same as \"Save to\" folder (or Downloads)"
                            : (s.downloadFolderPath as NSString).abbreviatingWithTildeInPath
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") {
                        if let url = Panels.pickFolder() { s.downloadFolderPath = url.path }
                    }
                    if !s.downloadFolderPath.isEmpty {
                        Button("Reset") { s.downloadFolderPath = "" }
                    }
                }
                TextField("File name template", text: $s.downloadFilenameTemplate)
                    .font(.system(.body, design: .monospaced))
                Hint(
                    "yt-dlp output template. %(title)s is the video title, %(uploader)s the channel, %(id)s the video id."
                )
            }

            Section("What to download") {
                Toggle("Audio only", isOn: $s.downloadAudioOnly)
                Picker("Audio format", selection: $s.downloadAudioFormat) {
                    ForEach(Self.audioFormats, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!s.downloadAudioOnly)
                IntRow(title: "Audio quality", value: $s.downloadAudioQuality)
                    .disabled(!s.downloadAudioOnly)
                Toggle("Embed cover art", isOn: $s.downloadEmbedCoverArt)
                    .disabled(!s.downloadAudioOnly)
                Hint(
                    "Quality 0 (best) to 10 (smallest) for MP3 and similar. \"best\" keeps the original audio without re-encoding."
                )
            }

            Section("Video") {
                Picker("Container", selection: $s.downloadVideoContainer) {
                    ForEach(Self.containers, id: \.self) { Text($0).tag($0) }
                }
                .disabled(s.downloadAudioOnly)
                IntRow(title: "Max height", unit: "px", value: $s.downloadMaxHeight)
                    .disabled(s.downloadAudioOnly)
                Hint("0 means the best available. Use 1080 or 720 to cap the resolution.")
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
                    "When off, a video link inside a playlist downloads only that video. The prefix is added in front of the file name template and is empty for single videos."
                )
            }

            Section("After downloading") {
                Toggle("Convert with ClipShift after each download", isOn: $s.downloadThenConvert)
                Toggle(
                    "Move the downloaded original to the Trash after converting",
                    isOn: $s.deleteOriginalAfterConvert
                )
                .disabled(!s.downloadThenConvert)
                Hint(
                    "Uses the Format and Quality chosen in the main window, plus your Video/Audio and Output settings. If the output folder is \"same as source\", converted files stay next to the download, including inside playlist folders."
                )
            }

            Section("Extras") {
                Toggle(
                    "Embed metadata (title, artist, album, year…)", isOn: $s.downloadEmbedMetadata)
                TextField("Extra yt-dlp arguments", text: $s.downloadExtraArgs, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                Hint(
                    "Advanced. Added to every download, for example: --cookies-from-browser safari")
            }

            ResetSection { s.resetDownloads() }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject private var s = Settings.shared
    @StateObject private var model = SettingsModel()

    private var confirmResetAll: Bool {
        get { model.confirmResetAll }
        nonmutating set { model.confirmResetAll = newValue }
    }

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Write a log file", isOn: $s.logEnabled)
                IntRow(title: "Rotate when larger than", unit: "MB", value: $s.logMaxMB)
                    .disabled(!s.logEnabled)
                HStack {
                    Text((Log.fileURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                    }
                }
            }

            ResetSection { s.resetAdvanced() }

            Section("Everything") {
                HStack {
                    Hint("Resets every tab, including the ffmpeg path.")
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) { confirmResetAll = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to defaults?", isPresented: $model.confirmResetAll)
        {
            Button("Reset All", role: .destructive) { s.resetAll() }
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var testResult: String?
    @Published var confirmResetAll = false
    @Published var ytdlpTestResult: String?
}
