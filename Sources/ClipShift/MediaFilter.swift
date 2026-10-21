import Foundation
import UniformTypeIdentifiers

enum MediaFilter {
    static let maxFolderFiles = 100
    static let maxVisitedEntries = 20_000

    /// Extensions the system may not map to movie/audio types.
    static let extraExtensions: [String] = [
        "mkv", "webm", "flv", "avi", "wmv", "ts", "m2ts", "mts", "m4v",
        "opus", "flac", "ogg", "oga", "wma", "mpg", "mpeg", "3gp",
    ]

    static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extraExtensions.contains(ext) { return true }
        guard let t = UTType(filenameExtension: ext) else { return false }
        return t.conforms(to: .movie) || t.conforms(to: .audio)
    }

    enum FolderScan {
        case files([URL])
        case tooMany
    }

    static func scan(_ folder: URL) -> FolderScan {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard
            let e = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return .files([]) }

        var found: [URL] = []
        var visited = 0
        for case let url as URL in e {
            visited += 1
            if visited > maxVisitedEntries { return .tooMany }
            guard (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else { continue }
            if isMedia(url) {
                found.append(url)
                if found.count > maxFolderFiles { return .tooMany }
            }
        }
        found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return .files(found)
    }
}
