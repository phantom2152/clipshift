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
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in ConversionManager.shared.add([url]) }
                }
            }
            return true
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

    private var fileList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(manager.jobs.count) file\(manager.jobs.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Files…") { manager.add(Panels.pickFiles()) }
                Button("Clear Finished") { manager.clearFinished() }
            }
            List(manager.jobs) { job in
                JobRow(job: job) { manager.remove(job) }
            }
            .listStyle(.inset)
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
    let onRemove: () -> Void

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
            if job.state != .running {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch job.state {
        case .waiting: return "film"
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

    private var statusText: String {
        switch job.state {
        case .waiting: return "Waiting"
        case .running: return ""
        case .done: return "Done → \(job.output?.lastPathComponent ?? "")"
        case .failed(let msg): return msg
        case .cancelled: return "Cancelled"
        }
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var format = Settings.shared.defaultFormat
    @Published var quality = Settings.shared.defaultQuality
    @Published var dropTargeted = false

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
