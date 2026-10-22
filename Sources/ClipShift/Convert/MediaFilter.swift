import Foundation
import UniformTypeIdentifiers

/// Decides what counts as media and scans dropped folders. Everything here is thread-safe
/// and takes its limits as a value, so folder scans can run off the main thread.
enum MediaFilter {
    struct Limits: Sendable {
        var maxFiles: Int
        var maxVisited: Int
        var extras: [String]
    }

    struct Classified: Sendable {
        var files: [URL] = []
        var rejectedFolders: [String] = []
        var skippedFiles = 0
    }

    @MainActor
    static func currentLimits() -> Limits {
        let s = AppSettings.shared
        return Limits(
            maxFiles: max(1, s.maxFolderFiles),
            maxVisited: max(1, s.maxVisitedEntries),
            extras: s.extraExtensions)
    }

    /// Extensions treated as audio even if macOS doesn't know them.
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "wma", "aac", "aiff",
    ]

    static func isMedia(_ url: URL, extras: [String]) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extras.contains(ext) || audioExtensions.contains(ext) { return true }
        guard let t = UTType(filenameExtension: ext) else { return false }
        return t.conforms(to: .movie) || t.conforms(to: .audio)
    }

    static func isAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .audio) ?? false
    }

    /// Sorts dropped items into media files, folders that were too big, and skipped files.
    static func classify(_ urls: [URL], limits: Limits) -> Classified {
        var out = Classified()
        for url in urls where url.isFileURL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                continue
            }
            if isDir.boolValue {
                if let files = scan(url, limits: limits) {
                    out.files += files
                } else {
                    out.rejectedFolders.append(url.lastPathComponent)
                }
            } else if isMedia(url, extras: limits.extras) {
                out.files.append(url)
            } else {
                out.skippedFiles += 1
            }
        }
        return out
    }

    /// Media files under `folder`, or nil when it has more than the limits allow.
    private static func scan(_ folder: URL, limits: Limits) -> [URL]? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard
            let e = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var found: [URL] = []
        var visited = 0
        for case let url as URL in e {
            visited += 1
            if visited > limits.maxVisited { return nil }
            guard (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else { continue }
            if isMedia(url, extras: limits.extras) {
                found.append(url)
                if found.count > limits.maxFiles { return nil }
            }
        }
        found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return found
    }
}
