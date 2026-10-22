import SwiftUI

struct JobRow: View {
    @ObservedObject var job: Job
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(job.state.phase.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.input.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.state == .running {
                    if job.indeterminate {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: job.progress)
                    }
                    if settings.showSpeedETA, let detail = runningDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(job.state.phase.isError ? Color.red : Color.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            if job.state == .running && !job.indeterminate {
                Text("\(Int(job.progress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if job.state == .done, let out = job.output {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([out])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch job.state {
        case .waiting: return MediaFilter.isAudio(job.input) ? "waveform" : "film"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var sourceInfo: String {
        var parts: [String] = []
        let ext = job.input.pathExtension.uppercased()
        if !ext.isEmpty { parts.append(ext) }
        if let size = job.fileSize { parts.append(Fmt.bytes(size)) }
        return parts.joined(separator: " · ")
    }

    private var statusText: String {
        switch job.state {
        case .waiting: return sourceInfo
        case .running: return ""
        case .done:
            var text = "Done → \(job.output?.lastPathComponent ?? "")"
            if settings.showSizeChange, let a = job.fileSize, let b = job.outputSize {
                text += "\n" + sizeChange(a, b)
            }
            return text
        case .failed(let msg): return msg
        case .cancelled: return "Cancelled · \(sourceInfo)"
        }
    }

    private var runningDetail: String? {
        guard let sp = job.speed, job.duration > 0 else { return nil }
        let remaining = max(0, job.duration * (1 - job.progress)) / sp
        return "\(String(format: "%.1f", sp))× · \(Fmt.clock(remaining)) left"
    }

    private func sizeChange(_ a: Int64, _ b: Int64) -> String {
        var text = "\(Fmt.bytes(a)) → \(Fmt.bytes(b))"
        if a > 0 {
            let pct = Int((Double(b - a) / Double(a) * 100).rounded())
            text += pct < 0 ? " (−\(abs(pct))%)" : pct > 0 ? " (+\(pct)%)" : " (same size)"
        }
        return text
    }
}
