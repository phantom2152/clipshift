import SwiftUI

@main
struct ClipShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A single window (not WindowGroup, which would allow ⌘N to open copies).
        Window("ClipShift", id: "main") {
            ContentView()
        }
        .defaultSize(width: 620, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") { ConversionManager.shared.add(Panels.pickFiles()) }
                    .keyboardShortcut("o")
            }
        }

        // Gives the "Settings…" menu item and ⌘, for free.
        SwiftUI.Settings {
            SettingsView()
        }
    }
}
