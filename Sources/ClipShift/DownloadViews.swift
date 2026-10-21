import SwiftUI

struct DownloadRow: View {
    @ObservedObject var job: DownloadJob
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.title ?? job.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.state == .downloading {
                    if job.indeterminate {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: job.progress)
                    }
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                } else if job.state == .processing {
                    ProgressView().progressViewStyle(.linear)
                    Text(job.stage).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            if job.state == .downloading && !job.indeterminate {
                Text("\(Int(job.progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
            if job.state.canRetry {
                Button("Retry", action: onRetry)
            }
            if job.state == .done, !job.outputs.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        var parts: [String] = []
        if let i = job.itemText { parts.append("Item \(i)") }
        if let sp = job.speed, sp.isFinite, sp >= 0 {
            parts.append(
                ByteCountFormatter.string(fromByteCount: Int64(sp), countStyle: .file) + "/s")
        }
        if let e = job.eta, e.isFinite, e >= 0 { parts.append("\(Self.clock(e)) left") }
        return parts.joined(separator: " · ")
    }

    private static func clock(_ secs: Double) -> String {
        let t = Int(secs.rounded())
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var iconName: String {
        switch job.state {
        case .waiting: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .processing: return "gearshape.2"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .done: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    private var statusIsError: Bool {
        if case .failed = job.state { return true }
        return false
    }

    private var statusText: String {
        switch job.state {
        case .waiting: return "Up next"
        case .downloading, .processing: return ""
        case .done:
            var t: String
            switch job.outputs.count {
            case 0: t = "Done"
            case 1: t = "Done → \(job.outputs[0].lastPathComponent)"
            default: t = "Done → \(job.outputs.count) files"
            }
            if let n = job.note { t += "\n" + n }
            return t
        case .failed(let msg): return msg
        case .cancelled: return "Cancelled"
        }
    }
}
