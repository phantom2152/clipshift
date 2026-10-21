import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static func pickFiles() -> [URL] {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes =
            [.movie, .audio]
            + MediaFilter.extraExtensions.compactMap { UTType(filenameExtension: $0) }
        p.message = "Choose video or audio files, or folders, to convert"
        return p.runModal() == .OK ? p.urls : []
    }

    static func pickFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        return p.runModal() == .OK ? p.url : nil
    }

    static func pickExecutable() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        let current = URL(fileURLWithPath: Settings.shared.resolvedFFmpegPath)
            .deletingLastPathComponent()
        let fallback = URL(fileURLWithPath: Factory.ffmpegPath).deletingLastPathComponent()
        p.directoryURL = FileManager.default.fileExists(atPath: current.path) ? current : fallback
        p.message = "Select the ffmpeg binary"
        p.prompt = "Select"
        return p.runModal() == .OK ? p.url : nil
    }
}
