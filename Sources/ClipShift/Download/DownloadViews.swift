import SwiftUI

/// The header, buttons and list for the download queue.
struct DownloadListSection: View {
    @ObservedObject private var downloads = DownloadManager.shared
    /// Taller when there is no convert list sharing the window.
    let expandToFill: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Fmt.count(downloads.jobs.count, "download"))
                    .foregroundStyle(.secondary)
                Spacer()
                if downloads.isRunning {
                    Button("Cancel Downloads") { downloads.cancelAll() }
                }
                Button("Clear Finished") { downloads.clearFinished() }
                    .disabled(!downloads.jobs.contains { $0.state == .done })
                Button("Clear All") { downloads.clearAll() }
                    .disabled(!downloads.jobs.contains { !$0.state.isBusy })
            }
            List(downloads.jobs) { job in
                DownloadRow(
                    job: job,
                    onRetry: { downloads.retry(job) },
                    onCancel: { downloads.cancel(job) }
                )
                .contextMenu {
                    if job.state.isBusy || job.state == .waiting {
                        Button("Cancel") { downloads.cancel(job) }
                    }
                    if !job.state.isBusy {
                        Button("Remove") { downloads.remove(job) }
                    }
                    if job.state.canRetry {
                        Button("Retry") { downloads.retry(job) }
                    }
                    if !job.outputs.isEmpty {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: expandToFill ? .infinity : 190)
        }
    }
}

struct DownloadRow: View {
    @ObservedObject var job: DownloadJob
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(job.state.phase.color)
                    .frame(width: 28)

                if job.isPlaylist { playlistSummary } else { singleSummary }

                if let pct = percentText {
                    Text(pct).monospacedDigit().foregroundStyle(.secondary)
                }
                if job.state.isBusy || job.state == .waiting {
                    Button("Cancel", action: onCancel)
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
                if job.isPlaylist {
                    Button {
                        job.expanded.toggle()
                    } label: {
                        Image(systemName: job.expanded ? "chevron.down" : "chevron.right")
                            .frame(width: 16)
                    }
                    .buttonStyle(.borderless)
                    .help(job.expanded ? "Hide songs" : "Show songs")
                }
            }

            if job.isPlaylist && job.expanded { trackList }
        }
        .padding(.vertical, 4)
    }

    // MARK: Single video

    private var singleSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title ?? job.url)
                .lineLimit(1)
                .truncationMode(.middle)
            if job.state == .downloading {
                songBar
                if !detail.isEmpty { detailLine }
            } else if job.state == .processing {
                ProgressView().progressViewStyle(.linear)
                Text(job.stage).font(.caption).foregroundStyle(.secondary)
            } else {
                statusLabel
            }
        }
    }

    // MARK: Playlist

    private var currentSongLine: String {
        let name = job.title ?? "Starting…"
        if let i = job.tracks.last?.id, let n = job.playlistCount { return "\(name) (\(i)/\(n))" }
        return name
    }

    private var playlistSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.playlistTitle ?? job.url)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if job.state.isBusy {
                Text(currentSongLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if job.state == .downloading {
                    songBar
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                ProgressView(value: job.overall)
                    .controlSize(.mini)
                if job.state == .processing {
                    Text(job.stage).font(.caption).foregroundStyle(.secondary)
                } else if !detail.isEmpty {
                    detailLine
                }
            } else {
                statusLabel
            }
        }
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(job.tracks) { TrackLine(track: $0) }
            }
            .padding(.leading, 40)
            .padding(.trailing, 4)
        }
        .frame(maxHeight: 180)
    }

    // MARK: Shared pieces

    @ViewBuilder
    private var songBar: some View {
        if job.indeterminate {
            ProgressView().progressViewStyle(.linear)
        } else {
            ProgressView(value: job.progress)
        }
    }

    private var detailLine: some View {
        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption)
            .foregroundStyle(job.state.phase.isError ? Color.red : Color.secondary)
            .lineLimit(4)
            .textSelection(.enabled)
    }

    /// Playlists show whole-playlist progress, single videos show their own.
    private var percentText: String? {
        guard job.state.isBusy else { return nil }
        if job.isPlaylist { return "\(Int(job.overall * 100))%" }
        if job.state == .downloading && !job.indeterminate { return "\(Int(job.progress * 100))%" }
        return nil
    }

    private var detail: String {
        var parts: [String] = []
        if let sp = job.speed, sp.isFinite, sp >= 0 {
            parts.append(Fmt.bytes(Int64(sp)) + "/s")
        }
        if let e = job.eta, e.isFinite, e >= 0 { parts.append("\(Fmt.clock(e)) left") }
        return parts.joined(separator: " · ")
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

    private var statusText: String {
        switch job.state {
        case .waiting: return "Up next"
        case .downloading, .processing: return ""
        case .done:
            var t: String
            switch job.outputs.count {
            case 0: t = "Done"
            case 1: t = "Done → \(job.outputs[0].lastPathComponent)"
            default:
                t = "Done → \(job.outputs.count) files"
                if let n = job.playlistCount, n > job.outputs.count { t += " of \(n)" }
            }
            if let n = job.note { t += "\n" + n }
            return t
        case .failed(let msg): return msg
        case .cancelled: return "Cancelled"
        }
    }
}

struct TrackLine: View {
    let track: DownloadJob.Track

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(track.phase.color)
                .frame(width: 16)
            Text(track.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            status
        }
        .font(.callout)
    }

    @ViewBuilder
    private var status: some View {
        switch track.state {
        case .downloading:
            if track.known {
                ProgressView(value: track.progress).frame(width: 90)
                Text("\(Int(track.progress * 100))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            } else {
                ProgressView().controlSize(.small)
            }
        case .processing:
            Text(track.stage).font(.caption).foregroundStyle(.secondary)
        case .done:
            Text("Done").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Text("Didn't finish").font(.caption).foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch track.state {
        case .downloading: return "arrow.down.circle"
        case .processing: return "gearshape"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }
}
