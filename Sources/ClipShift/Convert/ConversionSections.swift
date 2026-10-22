import SwiftUI

/// The header, buttons and selectable list for the convert queue.
struct ConvertListSection: View {
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @Local private var selection = Set<UUID>()
    @Local private var showClearAllConfirm = false

    private var countLabel: String {
        var s = Fmt.count(manager.jobs.count, "file")
        if !selection.isEmpty { s += " · \(selection.count) selected" }
        return s
    }

    private var hasRemovable: Bool { manager.jobs.contains { $0.state != .running } }

    private func removeSelected() {
        manager.remove(ids: selection)
        selection.removeAll()
    }

    private func clearAllTapped() {
        if manager.jobs.count > settings.clearAllConfirmThreshold {
            showClearAllConfirm = true
        } else {
            manager.clearAll()
            selection.removeAll()
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(countLabel).foregroundStyle(.secondary)
                Spacer()
                Button("Add Files…") { manager.add(Panels.pickFiles()) }
                Button("Remove Selected") { removeSelected() }
                    .disabled(selection.isEmpty)
                Button("Clear Finished") { manager.clearFinished() }
                    .disabled(!manager.jobs.contains { $0.state == .done })
                Button("Clear All") { clearAllTapped() }
                    .disabled(!hasRemovable)
            }
            List(manager.jobs, selection: $selection) { job in
                JobRow(job: job)
            }
            .listStyle(.inset)
            .onDeleteCommand { removeSelected() }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button("Remove") {
                        manager.remove(ids: ids)
                        selection.subtract(ids)
                    }
                    let outputs = manager.jobs
                        .filter { ids.contains($0.id) }
                        .compactMap { $0.output ?? $0.input }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                }
            }

            Text("Click to select · ⌘-click for several · ⇧-click for a range · Delete to remove")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Remove all \(manager.jobs.count) files from the list?",
            isPresented: $showClearAllConfirm
        ) {
            Button("Clear All", role: .destructive) {
                manager.clearAll()
                selection.removeAll()
            }
        } message: {
            Text("Your original files are not deleted. A running conversion is kept.")
        }
    }
}

/// Format, quality, output folder and the Convert / Cancel button.
struct ConvertOptionsPanel: View {
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = AppSettings.shared

    private var folderLabel: String {
        settings.outputFolderPath.isEmpty
            ? "Same folder as source"
            : (settings.outputFolderPath as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Picker("Format", selection: $manager.format) {
                        ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Quality", selection: $manager.quality) {
                        ForEach(Quality.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(!manager.format.usesQuality)
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
                        Button("Convert") { manager.start() }
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
