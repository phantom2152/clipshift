import SwiftUI

struct GeneralTab: View {
    @ObservedObject private var s = AppSettings.shared

    private static let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Format", selection: $s.defaultFormat) {
                    ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Quality", selection: $s.defaultQuality) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Remember the last used format and quality", isOn: $s.rememberLastUsed)
                Hint(
                    "When on, the main window starts with what you last converted with. The defaults above are used on first launch, or when this is off."
                )
            }

            Section("When work finishes") {
                Toggle("Show finished files in Finder", isOn: $s.revealWhenDone)
                Toggle("Play a sound", isOn: $s.playSoundWhenDone)
                HStack {
                    Picker("Sound", selection: $s.soundName) {
                        ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Preview") { NSSound(named: NSSound.Name(s.soundName))?.play() }
                }
                .disabled(!s.playSoundWhenDone)
                Toggle(
                    "Send a notification when ClipShift is in the background",
                    isOn: $s.notifyWhenDone)
                Hint("Applies to both conversions and downloads.")
            }

            Section("While working") {
                Toggle("Keep the Mac awake", isOn: $s.preventSleep)
                Toggle("Show conversion progress on the Dock icon", isOn: $s.showDockProgress)
                Toggle("Show speed and time left on rows", isOn: $s.showSpeedETA)
            }

            Section("Window and lists") {
                Toggle("Quit when the last window closes", isOn: $s.quitWhenLastWindowCloses)
                Stepper(value: $s.clearAllConfirmThreshold, in: 0...10_000) {
                    Text("Confirm Clear All above \(s.clearAllConfirmThreshold) files")
                }
                Hint("Set to 0 to always ask.")
                Toggle("Show before/after file size on finished rows", isOn: $s.showSizeChange)
            }

            ResetSection { s.reset(.general) }
        }
        .formStyle(.grouped)
    }
}
