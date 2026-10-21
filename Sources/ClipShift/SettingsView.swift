import SwiftUI

struct SettingsView: View {
    @ObservedObject private var s = Settings.shared
    @StateObject private var model = SettingsModel()

    private var testResult: String? {
        get { model.testResult }
        nonmutating set { model.testResult = newValue }
    }

    private var ffmpegExists: Bool {
        FileManager.default.isExecutableFile(atPath: s.resolvedFFmpegPath)
    }

    var body: some View {
        Form {
            Section("ffmpeg") {
                HStack {
                    TextField("Path", text: $s.ffmpegPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let url = Panels.pickExecutable() { s.ffmpegPath = url.path }
                    }
                }
                HStack {
                    if ffmpegExists {
                        Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not found or not executable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Reset to Default") {
                        s.ffmpegPath = Settings.defaultFFmpegPath
                        testResult = nil
                    }
                    Button("Test") { testFFmpeg() }.disabled(!ffmpegExists)
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Defaults") {
                Picker("Format", selection: $s.defaultFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Quality", selection: $s.defaultQuality) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Save to")
                    Spacer()
                    Text(
                        s.outputFolderPath.isEmpty
                            ? "Same folder as source"
                            : (s.outputFolderPath as NSString).abbreviatingWithTildeInPath
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    Button("Choose…") {
                        if let url = Panels.pickFolder() { s.outputFolderPath = url.path }
                    }
                    if !s.outputFolderPath.isEmpty {
                        Button("Reset") { s.outputFolderPath = "" }
                    }
                }
            }

            Section("Behavior") {
                Toggle("Overwrite existing files (otherwise keep both)", isOn: $s.overwriteExisting)
                Toggle("Show converted files in Finder when done", isOn: $s.revealWhenDone)
                Toggle("Play a sound when done", isOn: $s.playSoundWhenDone)
                Toggle("Quit when the last window closes", isOn: $s.quitWhenLastWindowCloses)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
    }

    private func testFFmpeg() {
        let path = s.resolvedFFmpegPath
        testResult = "Running…"
        Task {
            let text = await Task.detached { () -> String in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = ["-version"]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return "Could not run: \(error.localizedDescription)" }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return String(decoding: data, as: UTF8.self)
                    .split(separator: "\n").first.map(String.init) ?? "No output from ffmpeg."
            }.value
            testResult = text
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var testResult: String?
}
