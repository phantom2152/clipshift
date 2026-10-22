import AppKit

/// What SwiftUI's `App` can't do on its own: Dock-icon file drops, the quit warning,
/// and "quit when the last window closes".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.rotateIfNeeded()
        Log.write("---- ClipShift launched ----")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppSettings.shared.quitWhenLastWindowCloses
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag { showMainWindow() }
        return true
    }

    /// Files dropped on the Dock icon / "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        ConversionManager.shared.add(urls)
        showMainWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ConversionManager.shared.isRunning || DownloadManager.shared.isRunning {
            let alert = NSAlert()
            alert.messageText = "A conversion or download is still running"
            alert.informativeText = "Quitting now will cancel it."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Keep Running")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            ConversionManager.shared.cancelAll()
            DownloadManager.shared.cancelAll()
        }
        return .terminateNow
    }

    /// A closed SwiftUI window is only hidden, so it can be brought back by title.
    private func showMainWindow() {
        NSApp.windows.first { $0.title == "ClipShift" }?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
