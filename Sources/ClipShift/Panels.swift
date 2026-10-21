import AppKit

@MainActor
enum Panels {
    static func pickFiles() -> [URL] {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.message = "Choose video or audio files to convert"
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
        p.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        p.message = "Select the ffmpeg binary"
        p.prompt = "Select"
        return p.runModal() == .OK ? p.url : nil
    }
}
