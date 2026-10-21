import Foundation

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"

    @Published var ffmpegPath: String {
        didSet { UserDefaults.standard.set(ffmpegPath, forKey: "ffmpegPath") }
    }
    @Published var defaultFormat: OutputFormat {
        didSet { UserDefaults.standard.set(defaultFormat.rawValue, forKey: "defaultFormat") }
    }
    @Published var defaultQuality: Quality {
        didSet { UserDefaults.standard.set(defaultQuality.rawValue, forKey: "defaultQuality") }
    }
    /// Empty string = save next to the source file.
    @Published var outputFolderPath: String {
        didSet { UserDefaults.standard.set(outputFolderPath, forKey: "outputFolderPath") }
    }
    @Published var overwriteExisting: Bool {
        didSet { UserDefaults.standard.set(overwriteExisting, forKey: "overwriteExisting") }
    }
    @Published var revealWhenDone: Bool {
        didSet { UserDefaults.standard.set(revealWhenDone, forKey: "revealWhenDone") }
    }
    @Published var playSoundWhenDone: Bool {
        didSet { UserDefaults.standard.set(playSoundWhenDone, forKey: "playSoundWhenDone") }
    }
    @Published var quitWhenLastWindowCloses: Bool {
        didSet { UserDefaults.standard.set(quitWhenLastWindowCloses, forKey: "quitWhenLastWindowCloses") }
    }

    var resolvedFFmpegPath: String {
        (ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    var outputFolder: URL? {
        outputFolderPath.isEmpty ? nil : URL(fileURLWithPath: outputFolderPath, isDirectory: true)
    }

    private init() {
        let d = UserDefaults.standard
        ffmpegPath = d.string(forKey: "ffmpegPath") ?? Settings.detectFFmpeg()
        defaultFormat = OutputFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .mp4
        defaultQuality = Quality(rawValue: d.string(forKey: "defaultQuality") ?? "") ?? .medium
        outputFolderPath = d.string(forKey: "outputFolderPath") ?? ""
        overwriteExisting = d.object(forKey: "overwriteExisting") as? Bool ?? false
        revealWhenDone = d.object(forKey: "revealWhenDone") as? Bool ?? false
        playSoundWhenDone = d.object(forKey: "playSoundWhenDone") as? Bool ?? true
        quitWhenLastWindowCloses = d.object(forKey: "quitWhenLastWindowCloses") as? Bool ?? false
    }

    /// Homebrew default first, then the Intel Homebrew location, else the default anyway.
    private nonisolated static func detectFFmpeg() -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/ffmpeg"
    }
}
