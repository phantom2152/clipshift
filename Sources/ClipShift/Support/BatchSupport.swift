import AppKit

/// Keeps the Mac awake while a batch runs.
@MainActor
final class SleepGuard {
    private var token: NSObjectProtocol?

    func begin(_ reason: String) {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: reason)
    }

    func end() {
        if let token { ProcessInfo.processInfo.endActivity(token) }
        token = nil
    }
}

/// Sound, Finder reveal and notification shared by conversions and downloads.
@MainActor
enum WorkFinished {
    static func announce(finished: [URL], failed: Int, verb: String) {
        let s = AppSettings.shared
        if !finished.isEmpty {
            if s.playSoundWhenDone { NSSound(named: NSSound.Name(s.soundName))?.play() }
            if s.revealWhenDone { NSWorkspace.shared.activateFileViewerSelecting(finished) }
        }
        if s.notifyWhenDone, !NSApp.isActive, !(finished.isEmpty && failed == 0) {
            var body = "\(Fmt.count(finished.count, "file")) \(verb)"
            if failed > 0 { body += ", \(failed) failed" }
            Notifier.post(title: "ClipShift", body: body)
        }
    }
}
