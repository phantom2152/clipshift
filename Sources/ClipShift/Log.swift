import Foundation

enum Log {
    static func rotateIfNeeded(maxBytes: Int = 1_000_000) {
        queue.async {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let size = attrs?[.size] as? Int, size > maxBytes else { return }
            let old = fileURL.appendingPathExtension("old")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: fileURL, to: old)
        }
    }
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ClipShift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipshift.log")
    }()

    private static let queue = DispatchQueue(label: "clipshift.log")

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }
        queue.async {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
