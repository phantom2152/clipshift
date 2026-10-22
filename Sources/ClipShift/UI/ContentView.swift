import SwiftUI

struct ContentView: View {
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var downloads = DownloadManager.shared

    @Local private var urlText = ""
    @Local private var dropTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            urlBar
            NoticeBanner()
            if manager.jobs.isEmpty && downloads.jobs.isEmpty {
                dropZone
            } else {
                if !downloads.jobs.isEmpty {
                    DownloadListSection(expandToFill: manager.jobs.isEmpty)
                }
                if !manager.jobs.isEmpty { ConvertListSection() }
            }
            ConvertOptionsPanel()
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 460)
        .overlay {
            if dropTargeted && !(manager.jobs.isEmpty && downloads.jobs.isEmpty) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        // Accepts files and folders from Finder as well as web links from a browser.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
            if !files.isEmpty { manager.add(files) }
            if !links.isEmpty { downloads.addAndStart(links.joined(separator: " ")) }
            return !urls.isEmpty
        } isTargeted: {
            dropTargeted = $0
        }
        // A changed default applies right away when "remember last used" is off.
        .onChange(of: settings.defaultFormat) { _, new in
            if !settings.rememberLastUsed && !manager.isRunning { manager.format = new }
        }
        .onChange(of: settings.defaultQuality) { _, new in
            if !settings.rememberLastUsed && !manager.isRunning { manager.quality = new }
        }
    }

    // MARK: Download bar

    private var urlBar: some View {
        HStack(spacing: 8) {
            TextField("Paste a video or playlist link to download…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitURLs() }
            Button("Paste & Download") { pasteAndDownload() }
                .help("Download the link on the clipboard")
            Toggle("Audio only", isOn: $settings.downloadAudioOnly)
            Button("Download") { submitURLs() }
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitURLs() {
        if downloads.addAndStart(urlText) > 0 { urlText = "" }
    }

    private func pasteAndDownload() {
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            NoticeCenter.shared.post("The clipboard has no text to download.")
            return
        }
        downloads.addAndStart(text)
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop videos, audio or links here").font(.title2.weight(.semibold))
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
}
