import SwiftUI

enum Fmt {
    /// 75 → "1:15", 3700 → "1:01:40"
    static func clock(_ secs: Double) -> String {
        let t = Int(secs.rounded())
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// count(1, "file") → "1 file", count(3, "file") → "3 files"
    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// The coarse state every kind of row (conversion, download, playlist track) maps onto,
/// so icon colours and error styling are decided in one place.
enum JobPhase {
    case waiting, active, done, failed, cancelled

    var color: Color {
        switch self {
        case .done: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    var isError: Bool { self == .failed }
}
