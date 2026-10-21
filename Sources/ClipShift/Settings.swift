import Foundation

/// One value per quality level.
struct PerQuality<T: Codable & Equatable>: Codable, Equatable {
    var high: T
    var medium: T
    var small: T

    subscript(q: Quality) -> T {
        switch q {
        case .high: return high
        case .medium: return medium
        case .small: return small
        }
    }
}

/// Every factory default lives here and nowhere else.
enum Factory {
    // Tools
    static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
    static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    // General
    static let defaultFormat = OutputFormat.mp4
    static let defaultQuality = Quality.medium
    static let revealWhenDone = false
    static let playSoundWhenDone = true
    static let soundName = "Glass"
    static let quitWhenLastWindowCloses = false
    static let preventSleep = true
    static let showDockProgress = true
    static let notifyWhenDone = true
    static let showSpeedETA = true
    static let showSizeChange = true
    static let clearAllConfirmThreshold = 5

    // Output
    static let outputFolderPath = ""
    static let overwriteExisting = false
    static let convertedSuffix = " (converted)"
    /// "#" is replaced by the counter.
    static let duplicateFormat = " (#)"

    // Video
    static let x264Preset = "medium"
    static let crf = PerQuality<Int>(high: 18, medium: 23, small: 28)
    static let hevcQuality = PerQuality<Int>(high: 65, medium: 50, small: 35)
    static let vp9CRF = PerQuality<Int>(high: 24, medium: 31, small: 38)
    static let vp9CPUUsed = 4
    static let videoAACBitrate = 192
    static let opusBitrate = 128
    static let gifWidth = PerQuality<Int>(high: 960, medium: 640, small: 480)
    static let gifFPS = PerQuality<Int>(high: 15, medium: 12, small: 10)
    static let h264Hardware = false
    static let h264HWQuality = PerQuality<Int>(high: 65, medium: 50, small: 35)
    static let hardwareDecode = false

    // Audio
    static let mp3Quality = PerQuality<Int>(high: 0, medium: 2, small: 5)
    static let m4aBitrate = PerQuality<Int>(high: 256, medium: 192, small: 128)

    // Input
    static let maxFolderFiles = 500
    static let maxVisitedEntries = 20_000
    static let extraExtensions =
        "mkv, webm, flv, avi, wmv, ts, m2ts, mts, m4v, opus, flac, ogg, oga, wma, mpg, mpeg, 3gp"

    // Advanced
    static let logEnabled = true
    static let logMaxMB = 1
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    // MARK: Tools
    @Published var ffmpegPath: String { didSet { Self.put(ffmpegPath, "ffmpegPath") } }

    // MARK: General
    @Published var defaultFormat: OutputFormat {
        didSet { Self.put(defaultFormat.rawValue, "defaultFormat") }
    }
    @Published var defaultQuality: Quality {
        didSet { Self.put(defaultQuality.rawValue, "defaultQuality") }
    }
    @Published var revealWhenDone: Bool { didSet { Self.put(revealWhenDone, "revealWhenDone") } }
    @Published var playSoundWhenDone: Bool {
        didSet { Self.put(playSoundWhenDone, "playSoundWhenDone") }
    }
    @Published var soundName: String { didSet { Self.put(soundName, "soundName") } }
    @Published var quitWhenLastWindowCloses: Bool {
        didSet { Self.put(quitWhenLastWindowCloses, "quitWhenLastWindowCloses") }
    }
    @Published var clearAllConfirmThreshold: Int {
        didSet { Self.put(clearAllConfirmThreshold, "clearAllConfirmThreshold") }
    }

    @Published var preventSleep: Bool { didSet { Self.put(preventSleep, "preventSleep") } }
    @Published var showDockProgress: Bool {
        didSet { Self.put(showDockProgress, "showDockProgress") }
    }
    @Published var notifyWhenDone: Bool { didSet { Self.put(notifyWhenDone, "notifyWhenDone") } }
    @Published var showSpeedETA: Bool { didSet { Self.put(showSpeedETA, "showSpeedETA") } }
    @Published var showSizeChange: Bool { didSet { Self.put(showSizeChange, "showSizeChange") } }

    // MARK: Output
    /// Empty string = save next to the source file.
    @Published var outputFolderPath: String {
        didSet { Self.put(outputFolderPath, "outputFolderPath") }
    }
    @Published var overwriteExisting: Bool {
        didSet { Self.put(overwriteExisting, "overwriteExisting") }
    }
    @Published var convertedSuffix: String {
        didSet { Self.put(convertedSuffix, "convertedSuffix") }
    }
    @Published var duplicateFormat: String {
        didSet { Self.put(duplicateFormat, "duplicateFormat") }
    }

    // MARK: Video
    @Published var x264Preset: String { didSet { Self.put(x264Preset, "x264Preset") } }
    @Published var crf: PerQuality<Int> { didSet { Self.putJSON(crf, "crf") } }
    @Published var hevcQuality: PerQuality<Int> {
        didSet { Self.putJSON(hevcQuality, "hevcQuality") }
    }
    @Published var h264Hardware: Bool { didSet { Self.put(h264Hardware, "h264Hardware") } }
    @Published var h264HWQuality: PerQuality<Int> {
        didSet { Self.putJSON(h264HWQuality, "h264HWQuality") }
    }
    @Published var hardwareDecode: Bool { didSet { Self.put(hardwareDecode, "hardwareDecode") } }
    @Published var vp9CRF: PerQuality<Int> { didSet { Self.putJSON(vp9CRF, "vp9CRF") } }
    @Published var vp9CPUUsed: Int { didSet { Self.put(vp9CPUUsed, "vp9CPUUsed") } }
    @Published var videoAACBitrate: Int { didSet { Self.put(videoAACBitrate, "videoAACBitrate") } }
    @Published var opusBitrate: Int { didSet { Self.put(opusBitrate, "opusBitrate") } }
    @Published var gifWidth: PerQuality<Int> { didSet { Self.putJSON(gifWidth, "gifWidth") } }
    @Published var gifFPS: PerQuality<Int> { didSet { Self.putJSON(gifFPS, "gifFPS") } }

    // MARK: Audio
    @Published var mp3Quality: PerQuality<Int> { didSet { Self.putJSON(mp3Quality, "mp3Quality") } }
    @Published var m4aBitrate: PerQuality<Int> { didSet { Self.putJSON(m4aBitrate, "m4aBitrate") } }

    // MARK: Input
    @Published var maxFolderFiles: Int { didSet { Self.put(maxFolderFiles, "maxFolderFiles") } }
    @Published var maxVisitedEntries: Int {
        didSet { Self.put(maxVisitedEntries, "maxVisitedEntries") }
    }
    @Published var extraExtensionsText: String {
        didSet { Self.put(extraExtensionsText, "extraExtensionsText") }
    }

    // MARK: Advanced
    @Published var logEnabled: Bool { didSet { Self.put(logEnabled, "logEnabled") } }
    @Published var logMaxMB: Int { didSet { Self.put(logMaxMB, "logMaxMB") } }

    // MARK: Derived

    var resolvedFFmpegPath: String {
        (ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
    }

    var outputFolder: URL? {
        outputFolderPath.isEmpty ? nil : URL(fileURLWithPath: outputFolderPath, isDirectory: true)
    }

    /// Parsed from the comma/space separated text field. Lowercased, no dots.
    var extraExtensions: [String] {
        extraExtensionsText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
    }

    // MARK: Init

    private init() {
        let d = UserDefaults.standard
        ffmpegPath = d.string(forKey: "ffmpegPath") ?? Settings.detectFFmpeg()

        defaultFormat =
            OutputFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? Factory.defaultFormat
        defaultQuality =
            Quality(rawValue: d.string(forKey: "defaultQuality") ?? "") ?? Factory.defaultQuality
        revealWhenDone = Self.bool("revealWhenDone", Factory.revealWhenDone)
        playSoundWhenDone = Self.bool("playSoundWhenDone", Factory.playSoundWhenDone)
        soundName = Self.string("soundName", Factory.soundName)
        quitWhenLastWindowCloses = Self.bool(
            "quitWhenLastWindowCloses", Factory.quitWhenLastWindowCloses)
        clearAllConfirmThreshold = Self.int(
            "clearAllConfirmThreshold", Factory.clearAllConfirmThreshold)

        preventSleep = Self.bool("preventSleep", Factory.preventSleep)
        showDockProgress = Self.bool("showDockProgress", Factory.showDockProgress)
        notifyWhenDone = Self.bool("notifyWhenDone", Factory.notifyWhenDone)
        showSpeedETA = Self.bool("showSpeedETA", Factory.showSpeedETA)
        showSizeChange = Self.bool("showSizeChange", Factory.showSizeChange)

        outputFolderPath = Self.string("outputFolderPath", Factory.outputFolderPath)
        overwriteExisting = Self.bool("overwriteExisting", Factory.overwriteExisting)
        convertedSuffix = Self.string("convertedSuffix", Factory.convertedSuffix)
        duplicateFormat = Self.string("duplicateFormat", Factory.duplicateFormat)

        x264Preset = Self.string("x264Preset", Factory.x264Preset)
        crf = Self.json("crf", Factory.crf)
        hevcQuality = Self.json("hevcQuality", Factory.hevcQuality)
        h264Hardware = Self.bool("h264Hardware", Factory.h264Hardware)
        h264HWQuality = Self.json("h264HWQuality", Factory.h264HWQuality)
        hardwareDecode = Self.bool("hardwareDecode", Factory.hardwareDecode)
        vp9CRF = Self.json("vp9CRF", Factory.vp9CRF)
        vp9CPUUsed = Self.int("vp9CPUUsed", Factory.vp9CPUUsed)
        videoAACBitrate = Self.int("videoAACBitrate", Factory.videoAACBitrate)
        opusBitrate = Self.int("opusBitrate", Factory.opusBitrate)
        gifWidth = Self.json("gifWidth", Factory.gifWidth)
        gifFPS = Self.json("gifFPS", Factory.gifFPS)

        mp3Quality = Self.json("mp3Quality", Factory.mp3Quality)
        m4aBitrate = Self.json("m4aBitrate", Factory.m4aBitrate)

        maxFolderFiles = Self.int("maxFolderFiles", Factory.maxFolderFiles)
        maxVisitedEntries = Self.int("maxVisitedEntries", Factory.maxVisitedEntries)
        extraExtensionsText = Self.string("extraExtensionsText", Factory.extraExtensions)

        logEnabled = Self.bool("logEnabled", Factory.logEnabled)
        logMaxMB = Self.int("logMaxMB", Factory.logMaxMB)
    }

    // MARK: Resets (one per tab)

    func resetGeneral() {
        defaultFormat = Factory.defaultFormat
        defaultQuality = Factory.defaultQuality
        revealWhenDone = Factory.revealWhenDone
        playSoundWhenDone = Factory.playSoundWhenDone
        soundName = Factory.soundName
        quitWhenLastWindowCloses = Factory.quitWhenLastWindowCloses
        clearAllConfirmThreshold = Factory.clearAllConfirmThreshold
        preventSleep = Factory.preventSleep
        showDockProgress = Factory.showDockProgress
        notifyWhenDone = Factory.notifyWhenDone
        showSpeedETA = Factory.showSpeedETA
        showSizeChange = Factory.showSizeChange
    }

    func resetOutput() {
        outputFolderPath = Factory.outputFolderPath
        overwriteExisting = Factory.overwriteExisting
        convertedSuffix = Factory.convertedSuffix
        duplicateFormat = Factory.duplicateFormat
    }

    func resetVideo() {
        x264Preset = Factory.x264Preset
        crf = Factory.crf
        hevcQuality = Factory.hevcQuality
        h264Hardware = Factory.h264Hardware
        h264HWQuality = Factory.h264HWQuality
        hardwareDecode = Factory.hardwareDecode
        vp9CRF = Factory.vp9CRF
        vp9CPUUsed = Factory.vp9CPUUsed
        videoAACBitrate = Factory.videoAACBitrate
        opusBitrate = Factory.opusBitrate
        gifWidth = Factory.gifWidth
        gifFPS = Factory.gifFPS
    }

    func resetAudio() {
        mp3Quality = Factory.mp3Quality
        m4aBitrate = Factory.m4aBitrate
    }

    func resetInput() {
        maxFolderFiles = Factory.maxFolderFiles
        maxVisitedEntries = Factory.maxVisitedEntries
        extraExtensionsText = Factory.extraExtensions
    }

    func resetTools() {
        ffmpegPath = Settings.detectFFmpeg()
    }

    func resetAdvanced() {
        logEnabled = Factory.logEnabled
        logMaxMB = Factory.logMaxMB
    }

    func resetAll() {
        resetGeneral()
        resetOutput()
        resetVideo()
        resetAudio()
        resetInput()
        resetTools()
        resetAdvanced()
    }

    /// First existing candidate, else the factory default.
    nonisolated static func detectFFmpeg() -> String {
        Factory.ffmpegCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? Factory.ffmpegPath
    }

    // MARK: Storage helpers

    nonisolated private static func put(_ v: Any, _ key: String) {
        UserDefaults.standard.set(v, forKey: key)
    }
    nonisolated private static func putJSON<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { UserDefaults.standard.set(data, forKey: key) }
    }
    nonisolated private static func bool(_ k: String, _ def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: k) as? Bool ?? def
    }
    nonisolated private static func int(_ k: String, _ def: Int) -> Int {
        UserDefaults.standard.object(forKey: k) as? Int ?? def
    }
    nonisolated private static func string(_ k: String, _ def: String) -> String {
        UserDefaults.standard.string(forKey: k) ?? def
    }
    nonisolated private static func json<T: Decodable>(_ k: String, _ def: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: k),
            let v = try? JSONDecoder().decode(T.self, from: data)
        else { return def }
        return v
    }
}
