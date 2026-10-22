import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ConvertTab().tabItem { Label("Convert", systemImage: "film") }
            DownloadsTab().tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            ToolsTab().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            AdvancedTab().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 700, height: 540)
    }
}
