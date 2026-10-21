import Foundation

enum Log {
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ClipShift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipshift.log")
    }()

    private static let queue = DispatchQueue(label: "clipshift.log")

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "logEnabled") as? Bool ?? Factory.logEnabled
    }

    private static var maxBytes: Int {
        let mb = UserDefaults.standard.object(forKey: "logMaxMB") as? Int ?? Factory.logMaxMB
        return max(1, mb) * 1_000_000
    }

    static func write(_ message: String) {
        guard enabled else { return }
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

    /// Called at launch. Moves the log to clipshift.log.old when it is over the size limit.
    static func rotateIfNeeded() {
        let limit = maxBytes
        queue.async {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let size = attrs?[.size] as? Int, size > limit else { return }
            let old = fileURL.appendingPathExtension("old")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: fileURL, to: old)
        }
    }
}
