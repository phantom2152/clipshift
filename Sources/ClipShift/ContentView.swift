import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = Settings.shared
    @StateObject private var model = ContentViewModel()

    private var format: OutputFormat {
        get { model.format }
        nonmutating set { model.format = newValue }
    }
    private var quality: Quality {
        get { model.quality }
        nonmutating set { model.quality = newValue }
    }
    private var dropTargeted: Bool {
        get { model.dropTargeted }
        nonmutating set { model.dropTargeted = newValue }
    }

    /// Ask for confirmation in Clear All above this many files.
    private let clearAllConfirmThreshold = 5

    var body: some View {
        VStack(spacing: 14) {
            if manager.jobs.isEmpty { dropZone } else { fileList }
            optionsPanel
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 460)
        .overlay {
            if dropTargeted && !manager.jobs.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            let collector = URLCollector()
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { collector.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let urls = collector.all
                Task { @MainActor in ConversionManager.shared.add(urls) }
            }
            return true
        }
        .confirmationDialog(
            "Remove all \(manager.jobs.count) files from the list?",
            isPresented: $model.showClearAllConfirm
        ) {
            Button("Clear All", role: .destructive) {
                manager.clearAll()
                model.selection.removeAll()
            }
        } message: {
            Text("Your original files are not deleted. A running conversion is kept.")
        }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop videos here").font(.title2.weight(.semibold))
            Text("or").foregroundStyle(.secondary)
            Button("Choose Files…") { manager.add(Panels.pickFiles()) }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
    }

    // MARK: File list

    private var countLabel: String {
        let n = manager.jobs.count
        var s = "\(n) file\(n == 1 ? "" : "s")"
        if !model.selection.isEmpty { s += " · \(model.selection.count) selected" }
        return s
    }

    private var hasRemovable: Bool {
        manager.jobs.contains { $0.state != .running }
    }

    private func removeSelected() {
        manager.remove(ids: model.selection)
        model.selection.removeAll()
    }

    private func clearAllTapped() {
        if manager.jobs.count > clearAllConfirmThreshold {
            model.showClearAllConfirm = true
        } else {
            manager.clearAll()
            model.selection.removeAll()
        }
    }

    private var fileList: some View {
        VStack(spacing: 8) {
            HStack {
                Text(countLabel).foregroundStyle(.secondary)
                Spacer()
                Button("Add Files…") { manager.add(Panels.pickFiles()) }
                Button("Remove Selected") { removeSelected() }
                    .disabled(model.selection.isEmpty)
                Button("Clear Finished") { manager.clearFinished() }
                    .disabled(!manager.jobs.contains { $0.state == .done })
                Button("Clear All") { clearAllTapped() }
                    .disabled(!hasRemovable)
            }
            List(manager.jobs, selection: $model.selection) { job in
                JobRow(job: job)
            }
            .listStyle(.inset)
            .onDeleteCommand { removeSelected() }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button("Remove") {
                        manager.remove(ids: ids)
                        model.selection.subtract(ids)
                    }
                    let outputs = manager.jobs
                        .filter { ids.contains($0.id) }
                        .compactMap { $0.output ?? $0.input }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                }
            }

            Text(
                "Click to select · ⌘-click to pick several · ⇧-click for a range · Delete to remove · ⌘A selects all"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Options

    private var folderLabel: String {
        settings.outputFolderPath.isEmpty
            ? "Same folder as source"
            : (settings.outputFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private var optionsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Picker("Format", selection: $model.format) {
                        ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Quality", selection: $model.quality) {
                        ForEach(Quality.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(!format.usesQuality)
                    .frame(maxWidth: 220)
                }
                .disabled(manager.isRunning)

                HStack {
                    Text("Save to").foregroundStyle(.secondary)
                    Text(folderLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") {
                        if let url = Panels.pickFolder() { settings.outputFolderPath = url.path }
                    }
                    if !settings.outputFolderPath.isEmpty {
                        Button("Same as Source") { settings.outputFolderPath = "" }
                    }
                }
                .disabled(manager.isRunning)

                HStack {
                    Spacer()
                    if manager.isRunning {
                        Button("Cancel") { manager.cancelAll() }
                    } else {
                        Button("Convert") { manager.start(format: format, quality: quality) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!manager.hasPending)
                    }
                }
            }
            .padding(6)
        }
    }
}

struct JobRow: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
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
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
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

    private var isAudio: Bool {
        let ext = job.input.pathExtension.lowercased()
        if ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "wma", "aac", "aiff"].contains(ext) {
            return true
        }
        return UTType(filenameExtension: ext)?.conforms(to: .audio) ?? false
    }

    private var iconName: String {
        switch job.state {
        case .waiting: return isAudio ? "waveform" : "film"
        case .running: return "arrow.triangle.2.circlepath"
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

    private var sourceInfo: String {
        var parts: [String] = []
        let ext = job.input.pathExtension.uppercased()
        if !ext.isEmpty { parts.append(ext) }
        if let size = job.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var statusText: String {
        switch job.state {
        case .waiting: return sourceInfo
        case .running: return ""
        case .done: return "Done → \(job.output?.lastPathComponent ?? "")"
        case .failed(let msg): return msg
        case .cancelled: return "Cancelled · \(sourceInfo)"
        }
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var format = Settings.shared.defaultFormat
    @Published var quality = Settings.shared.defaultQuality
    @Published var dropTargeted = false
    @Published var selection = Set<UUID>()
    @Published var showClearAllConfirm = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        Settings.shared.$defaultFormat
            .dropFirst()
            .sink { [weak self] in self?.format = $0 }
            .store(in: &cancellables)
        Settings.shared.$defaultQuality
            .dropFirst()
            .sink { [weak self] in self?.quality = $0 }
            .store(in: &cancellables)
    }
}

final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ u: URL) {
        lock.lock()
        urls.append(u)
        lock.unlock()
    }
    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
