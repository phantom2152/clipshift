import Foundation

@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case waiting, downloading, processing, done
        case failed(String)
        case cancelled

        var isBusy: Bool { self == .downloading || self == .processing }
        var canRetry: Bool {
            switch self {
            case .failed, .cancelled: return true
            default: return false
            }
        }

        var phase: JobPhase {
            switch self {
            case .waiting: return .waiting
            case .downloading, .processing: return .active
            case .done: return .done
            case .failed: return .failed
            case .cancelled: return .cancelled
            }
        }
    }

    /// One song or video inside a playlist.
    struct Track: Identifiable, Equatable {
        enum State: Equatable { case downloading, processing, done, failed, cancelled }
        let id: Int  // position in the playlist
        var title: String
        var state: State = .downloading
        var progress = 0.0
        var stage = ""
        var known = false  // true once yt-dlp has reported a real percentage

        var isOpen: Bool { state == .downloading || state == .processing }

        var phase: JobPhase {
            switch state {
            case .downloading, .processing: return .active
            case .done: return .done
            case .failed: return .failed
            case .cancelled: return .cancelled
            }
        }
    }

    enum CloseReason { case succeeded, cancelled, failed }

    let id = UUID()
    let url: String
    var runner = ProcessRunner(stderrLimit: 4000, gracefulCancel: true)
    /// Whether this download was audio only (decides if converting it to a video format makes sense).
    var audioOnly = false
    /// Set when "Convert after download" was ticked as this link was queued. The format and
    /// quality are saved then, so later changes to the pickers don't affect it.
    var convertFormat: OutputFormat?
    var convertQuality: Quality?

    @Published var state: State = .waiting
    @Published var progress = 0.0
    @Published var indeterminate = true
    @Published var speed: Double?
    @Published var eta: Double?
    @Published var title: String?
    @Published var stage = ""
    @Published var outputs: [URL] = []
    @Published var note: String?

    @Published var playlistTitle: String?
    @Published var playlistCount: Int?
    @Published var tracks: [Track] = []
    @Published var expanded = false

    init(url: String) { self.url = url }

    var isPlaylist: Bool { (playlistCount ?? 0) > 1 }
    var doneCount: Int { tracks.filter { $0.state == .done }.count }

    /// Whole-playlist progress: finished songs plus the fraction of the current one.
    var overall: Double {
        guard let n = playlistCount, n > 0 else { return progress }
        let current = tracks.last(where: \.isOpen)?.progress ?? 0
        return min((Double(doneCount) + current) / Double(n), 1)
    }

    func reset() {
        progress = 0
        indeterminate = true
        speed = nil
        eta = nil
        stage = ""
        note = nil
        outputs = []
        tracks = []
        playlistTitle = nil
        playlistCount = nil
    }

    // MARK: Playlist tracks

    func updateTrack(index: Int, title: String?, fraction: Double?) {
        if let i = tracks.firstIndex(where: { $0.id == index }) {
            if let title, tracks[i].title != title { tracks[i].title = title }
            if tracks[i].state == .downloading, let f = fraction {
                tracks[i].progress = f
                tracks[i].known = true
            }
        } else {
            // A new item started. Anything still open never printed a file path:
            // if it had reached post-processing it has finished, otherwise it was skipped.
            for i in tracks.indices where tracks[i].isOpen {
                tracks[i].state = tracks[i].state == .processing ? .done : .failed
                if tracks[i].state == .done { tracks[i].progress = 1 }
            }
            var t = Track(id: index, title: title ?? "Track \(index)")
            if let f = fraction {
                t.progress = f
                t.known = true
            }
            tracks.append(t)
        }
    }

    func markCurrentTrackProcessing(_ name: String) {
        guard let i = tracks.indices.last, tracks[i].isOpen else { return }
        tracks[i].state = .processing
        tracks[i].stage = name
        tracks[i].progress = 1
    }

    /// yt-dlp printed a final file path, so the current item is complete.
    func currentTrackFinished() {
        guard let i = tracks.lastIndex(where: \.isOpen) else { return }
        tracks[i].state = .done
        tracks[i].progress = 1
    }

    func closeOpenTracks(_ reason: CloseReason) {
        for i in tracks.indices where tracks[i].isOpen {
            switch reason {
            case .cancelled: tracks[i].state = .cancelled
            case .failed: tracks[i].state = .failed
            case .succeeded:
                tracks[i].state = .done
                tracks[i].progress = 1
            }
        }
    }
}
