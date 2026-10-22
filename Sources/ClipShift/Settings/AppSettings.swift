import SwiftUI

/// Defaults that are also needed outside `AppSettings`. Every other default is written once,
/// right next to its property below.
enum AppDefaults {
    static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
    static let ytdlpPath = "/opt/homebrew/bin/yt-dlp"
    static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    static let ytdlpCandidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
    static let filenameTemplate = "%(title)s"
    static let convertedSuffix = " (converted)"
    static let logEnabled = true
    static let logMaxMB = 1
}

/// One value per quality level. Stored in UserDefaults as a small JSON string.
struct PerQuality<T: Codable & Equatable>: Codable, Equatable, RawRepresentable {
    var high: T
    var medium: T
    var small: T

    init(high: T, medium: T, small: T) {
        self.high = high
        self.medium = medium
        self.small = small
    }

    subscript(q: Quality) -> T {
        switch q {
        case .high: return high
        case .medium: return medium
        case .small: return small
        }
    }

    // RawRepresentable (String) is what lets @AppStorage hold this type.
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(PerQuality<T>.self, from: data)
        else { return nil }
        self = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // Written out by hand so RawRepresentable can never hijack the coding.
    private enum CodingKeys: String, CodingKey { case high, medium, small }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        high = try c.decode(T.self, forKey: .high)
        medium = try c.decode(T.self, forKey: .medium)
        small = try c.decode(T.self, forKey: .small)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(high, forKey: .high)
        try c.encode(medium, forKey: .medium)
        try c.encode(small, forKey: .small)
    }
}

enum SettingsGroup: CaseIterable {
    case general, convert, downloads, tools, advanced
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared: AppSettings = {
        AppSettings.migrateLegacyValues()
        return AppSettings()
    }()

    private init() {
        // @AppStorage normally publishes changes by itself. This makes sure every view that
        // watches the settings refreshes whenever any stored value changes (including resets).
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    // MARK: Tools
    @AppStorage("ffmpegPath") var ffmpegPath = AppSettings.detectFFmpeg()
    @AppStorage("ytdlpPath") var ytdlpPath = AppSettings.detectYTDLP()

    // MARK: General
    @AppStorage("defaultFormat") var defaultFormat: OutputFormat = .mp4
    @AppStorage("defaultQuality") var defaultQuality: Quality = .medium
    @AppStorage("rememberLastUsed") var rememberLastUsed = true
    @AppStorage("revealWhenDone") var revealWhenDone = false
    @AppStorage("playSoundWhenDone") var playSoundWhenDone = true
    @AppStorage("soundName") var soundName = "Glass"
    @AppStorage("quitWhenLastWindowCloses") var quitWhenLastWindowCloses = false
    @AppStorage("clearAllConfirmThreshold") var clearAllConfirmThreshold = 5
    @AppStorage("preventSleep") var preventSleep = true
    @AppStorage("showDockProgress") var showDockProgress = true
    @AppStorage("notifyWhenDone") var notifyWhenDone = true
    @AppStorage("showSpeedETA") var showSpeedETA = true
    @AppStorage("showSizeChange") var showSizeChange = true

    // MARK: Convert: output
    /// Empty string = save next to the source file.
    @AppStorage("outputFolderPath") var outputFolderPath = ""
    @AppStorage("overwriteExisting") var overwriteExisting = false
    @AppStorage("convertedSuffix") var convertedSuffix = AppDefaults.convertedSuffix
    /// "#" is replaced by the counter.
    @AppStorage("duplicateFormat") var duplicateFormat = " (#)"

    // MARK: Convert: video
    @AppStorage("x264Preset") var x264Preset = "medium"
    @AppStorage("crf") var crf = PerQuality<Int>(high: 18, medium: 23, small: 28)
    @AppStorage("hevcQuality") var hevcQuality = PerQuality<Int>(high: 65, medium: 50, small: 35)
    @AppStorage("h264Hardware") var h264Hardware = false
    @AppStorage("h264HWQuality") var h264HWQuality = PerQuality<Int>(
        high: 65, medium: 50, small: 35)
    @AppStorage("hardwareDecode") var hardwareDecode = false
    @AppStorage("vp9CRF") var vp9CRF = PerQuality<Int>(high: 24, medium: 31, small: 38)
    @AppStorage("vp9CPUUsed") var vp9CPUUsed = 4
    @AppStorage("videoAACBitrate") var videoAACBitrate = 192
    @AppStorage("opusBitrate") var opusBitrate = 128
    @AppStorage("gifWidth") var gifWidth = PerQuality<Int>(high: 960, medium: 640, small: 480)
    @AppStorage("gifFPS") var gifFPS = PerQuality<Int>(high: 15, medium: 12, small: 10)

    // MARK: Convert: audio
    @AppStorage("mp3Quality") var mp3Quality = PerQuality<Int>(high: 0, medium: 2, small: 5)
    @AppStorage("m4aBitrate") var m4aBitrate = PerQuality<Int>(high: 256, medium: 192, small: 128)

    // MARK: Convert: input
    @AppStorage("maxFolderFiles") var maxFolderFiles = 500
    @AppStorage("maxVisitedEntries") var maxVisitedEntries = 20_000
    @AppStorage("extraExtensionsText") var extraExtensionsText =
        "mkv, webm, flv, avi, wmv, m2ts, m4v, opus, flac, ogg, oga, wma, mpg, mpeg, 3gp"

    // MARK: Downloads
    /// Empty string = the Downloads folder.
    @AppStorage("downloadFolderPath") var downloadFolderPath = ""
    @AppStorage("downloadAudioOnly") var downloadAudioOnly = false
    @AppStorage("downloadAudioFormat") var downloadAudioFormat = "mp3"
    @AppStorage("downloadAudioQuality") var downloadAudioQuality = 0
    @AppStorage("downloadVideoContainer") var downloadVideoContainer = "mp4"
    @AppStorage("downloadMaxHeight") var downloadMaxHeight = 0
    @AppStorage("downloadFilenameTemplate") var downloadFilenameTemplate =
        AppDefaults.filenameTemplate
    @AppStorage("downloadPlaylists") var downloadPlaylists = false
    @AppStorage("downloadMaxPlaylistItems") var downloadMaxPlaylistItems = 50
    @AppStorage("downloadEmbedMetadata") var downloadEmbedMetadata = true
    @AppStorage("downloadEmbedCoverArt") var downloadEmbedCoverArt = true
    @AppStorage("downloadGroupPlaylists") var downloadGroupPlaylists = true
    /// Becomes "Playlist Name/" for playlists and nothing for single videos.
    @AppStorage("downloadPlaylistPrefix") var downloadPlaylistPrefix = "%(playlist_title)s/"
    @AppStorage("downloadExtraArgs") var downloadExtraArgs = ""
    @AppStorage("deleteOriginalAfterConvert") var deleteOriginalAfterConvert = true

    // MARK: Advanced
    @AppStorage("logEnabled") var logEnabled = AppDefaults.logEnabled
    @AppStorage("logMaxMB") var logMaxMB = AppDefaults.logMaxMB

    // MARK: Derived

    nonisolated static func resolve(_ path: String) -> String {
        (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    var resolvedFFmpegPath: String { Self.resolve(ffmpegPath) }
    var resolvedYTDLPPath: String { Self.resolve(ytdlpPath) }

    var outputFolder: URL? {
        outputFolderPath.isEmpty ? nil : URL(fileURLWithPath: outputFolderPath, isDirectory: true)
    }

    /// Download folder → ~/Downloads.
    var resolvedDownloadFolder: URL {
        if !downloadFolderPath.isEmpty {
            return URL(fileURLWithPath: downloadFolderPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Parsed from the comma/space separated text field. Lowercased, no dots.
    var extraExtensions: [String] {
        extraExtensionsText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
    }

    // MARK: Last used format and quality

    var lastFormat: OutputFormat? {
        OutputFormat(rawValue: UserDefaults.standard.string(forKey: "lastFormat") ?? "")
    }
    var lastQuality: Quality? {
        Quality(rawValue: UserDefaults.standard.string(forKey: "lastQuality") ?? "")
    }
    func saveLast(format: OutputFormat, quality: Quality) {
        UserDefaults.standard.set(format.rawValue, forKey: "lastFormat")
        UserDefaults.standard.set(quality.rawValue, forKey: "lastQuality")
    }

    // MARK: Resets

    /// Every key of each tab. Resetting removes the stored value, so the default declared
    /// above applies again. Keep this in step with the properties when adding a setting.
    private static let keys: [SettingsGroup: [String]] = [
        .general: [
            "defaultFormat", "defaultQuality", "rememberLastUsed", "revealWhenDone",
            "playSoundWhenDone", "soundName", "quitWhenLastWindowCloses",
            "clearAllConfirmThreshold", "preventSleep", "showDockProgress", "notifyWhenDone",
            "showSpeedETA", "showSizeChange",
        ],
        .convert: [
            "outputFolderPath", "overwriteExisting", "convertedSuffix", "duplicateFormat",
            "x264Preset", "crf", "hevcQuality", "h264Hardware", "h264HWQuality",
            "hardwareDecode", "vp9CRF", "vp9CPUUsed", "videoAACBitrate", "opusBitrate",
            "gifWidth", "gifFPS", "mp3Quality", "m4aBitrate", "maxFolderFiles",
            "maxVisitedEntries", "extraExtensionsText",
        ],
        .downloads: [
            "downloadFolderPath", "downloadAudioOnly", "downloadAudioFormat",
            "downloadAudioQuality", "downloadVideoContainer", "downloadMaxHeight",
            "downloadFilenameTemplate", "downloadPlaylists", "downloadMaxPlaylistItems",
            "downloadEmbedMetadata", "downloadEmbedCoverArt", "downloadGroupPlaylists",
            "downloadPlaylistPrefix", "downloadExtraArgs", "deleteOriginalAfterConvert",
        ],
        .advanced: ["logEnabled", "logMaxMB"],
    ]

    func reset(_ group: SettingsGroup) {
        if group == .tools {
            // Detected again right now, not at launch.
            ffmpegPath = Self.detectFFmpeg()
            ytdlpPath = Self.detectYTDLP()
            return
        }
        for key in Self.keys[group] ?? [] { UserDefaults.standard.removeObject(forKey: key) }
        objectWillChange.send()
    }

    func resetAll() {
        for group in SettingsGroup.allCases { reset(group) }
    }

    // MARK: Tool detection

    /// First existing candidate, else the factory default.
    nonisolated static func detectFFmpeg() -> String {
        AppDefaults.ffmpegCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? AppDefaults.ffmpegPath
    }

    nonisolated static func detectYTDLP() -> String {
        AppDefaults.ytdlpCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? AppDefaults.ytdlpPath
    }

    // MARK: Migration

    /// Older versions stored the per-quality values as JSON `Data`; they are now JSON text.
    /// Converts them once so existing tuned values survive.
    nonisolated private static func migrateLegacyValues() {
        let d = UserDefaults.standard
        let keys = [
            "crf", "hevcQuality", "h264HWQuality", "vp9CRF",
            "gifWidth", "gifFPS", "mp3Quality", "m4aBitrate",
        ]
        for key in keys {
            guard let data = d.data(forKey: key),
                let text = String(data: data, encoding: .utf8)
            else { continue }
            d.set(text, forKey: key)
        }
    }
}
