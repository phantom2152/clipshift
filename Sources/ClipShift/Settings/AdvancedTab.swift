import SwiftUI

struct AdvancedTab: View {
    @ObservedObject private var s = AppSettings.shared
    @Local private var confirmResetAll = false

    var body: some View {
        Form {
            Section("Logging") {
                Toggle("Write a log file", isOn: $s.logEnabled)
                IntRow(title: "Rotate when larger than", unit: "MB", value: $s.logMaxMB)
                    .disabled(!s.logEnabled)
                HStack {
                    Text((Log.fileURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                    }
                }
                Hint(
                    "The log records the full download links and any extra yt-dlp arguments you set, such as cookie options. Turn it off or clear it before sharing it."
                )
            }

            ResetSection { s.reset(.advanced) }

            Section("Everything") {
                HStack {
                    Hint("Resets every tab, including the tool paths.")
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) { confirmResetAll = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { s.resetAll() }
        }
    }
}
