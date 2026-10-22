import SwiftUI

struct ToolsTab: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            ToolSection(
                title: "ffmpeg", path: $s.ffmpegPath, resolved: s.resolvedFFmpegPath,
                detect: AppSettings.detectFFmpeg,
                versionArgs: ["-version"], stream: .stdout,
                describe: { $0.split(separator: "\n").first.map(String.init) ?? "No output from ffmpeg." },
                hint: "Auto-detect checks the Homebrew locations (Apple Silicon, then Intel).")

            ToolSection(
                title: "yt-dlp", path: $s.ytdlpPath, resolved: s.resolvedYTDLPPath,
                detect: AppSettings.detectYTDLP,
                versionArgs: ["--version"], stream: .stdout,
                describe: {
                    let v = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return v.isEmpty ? "No output from yt-dlp." : "yt-dlp version \(v)"
                },
                hint:
                    "Install with: brew install yt-dlp. Sites change often, so run brew upgrade yt-dlp if downloads start failing."
            )

            ResetSection(title: "Reset to Auto-detected") { s.reset(.tools) }
        }
        .formStyle(.grouped)
    }
}

/// One tool: path field, found/not found, auto-detect and a version test.
private struct ToolSection: View {
    let title: String
    @Binding var path: String
    let resolved: String
    let detect: () -> String
    let versionArgs: [String]
    let stream: ProcessRunner.Stream
    let describe: (String) -> String
    let hint: String

    @Local private var testResult: String?

    private var exists: Bool { FileManager.default.isExecutableFile(atPath: resolved) }

    var body: some View {
        Section(title) {
            HStack {
                TextField("Path", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    if let url = Panels.pickExecutable(name: title, startingAt: resolved) {
                        path = url.path
                    }
                }
            }
            HStack {
                if exists {
                    Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Not found or not executable", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Auto-detect") { path = detect() }
                Button("Test") { runTest() }.disabled(!exists)
            }
            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Hint(hint)
        }
        .onChange(of: path) { _, _ in testResult = nil }
    }

    private func runTest() {
        let exe = resolved
        testResult = "Running…"
        Task { @MainActor in
            if let out = await ProcessRunner.capture(exe, versionArgs, stream: stream) {
                testResult = describe(out)
            } else {
                testResult = "Could not run \(title)."
            }
        }
    }
}
