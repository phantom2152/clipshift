import Foundation
import UniformTypeIdentifiers

@MainActor
enum MediaFilter {
    static var maxFolderFiles: Int { max(1, Settings.shared.maxFolderFiles) }
    static var maxVisitedEntries: Int { max(1, Settings.shared.maxVisitedEntries) }
    static var extraExtensions: [String] { Settings.shared.extraExtensions }

    static func isMedia(_ url: URL, extras: [String]? = nil) -> Bool {
        let ext = url.pathExtension.lowercased()
        if (extras ?? extraExtensions).contains(ext) { return true }
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

        let maxFiles = maxFolderFiles
        let maxVisited = maxVisitedEntries
        let extras = extraExtensions

        var found: [URL] = []
        var visited = 0
        for case let url as URL in e {
            visited += 1
            if visited > maxVisited { return .tooMany }
            guard (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else { continue }
            if isMedia(url, extras: extras) {
                found.append(url)
                if found.count > maxFiles { return .tooMany }
            }
        }
        found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return .files(found)
    }
}
