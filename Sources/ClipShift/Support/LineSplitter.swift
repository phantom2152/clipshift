import Foundation

/// Turns arbitrary chunks of process output into complete lines.
/// Not thread-safe on its own; `ProcessRunner` guards it with its lock.
final class LineSplitter: @unchecked Sendable {
    private var data = Data()

    func feed(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 10) {
            lines.append(String(decoding: data[data.startIndex..<nl], as: UTF8.self))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    /// Whatever is left over without a trailing newline.
    func flush() -> String? {
        guard !data.isEmpty else { return nil }
        defer { data.removeAll() }
        return String(decoding: data, as: UTF8.self)
    }
}
