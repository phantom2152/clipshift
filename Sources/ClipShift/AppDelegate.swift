import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Settings.shared.quitWhenLastWindowCloses
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
        if ConversionManager.shared.isRunning {
            let alert = NSAlert()
            alert.messageText = "A conversion is still running"
            alert.informativeText = "Quitting now will cancel it."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Keep Running")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            ConversionManager.shared.cancelAll()
        }
        return .terminateNow
    }

    // MARK: Windows

    func showMainWindow() {
        if mainWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "ClipShift"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: ContentView())
            w.setContentSize(NSSize(width: 620, height: 560))
            w.minSize = NSSize(width: 540, height: 480)
            if !w.setFrameAutosaveName("ClipShiftMainWindow") { w.center() }
            mainWindow = w
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "ClipShift Settings"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.setContentSize(NSSize(width: 540, height: 520))
            w.center()
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openFiles() {
        ConversionManager.shared.add(Panels.pickFiles())
        showMainWindow()
    }

    // MARK: Menu

    private func buildMenu() {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let item = NSMenuItem()
            main.addItem(item)
            let menu = NSMenu(title: title)
            items.forEach { menu.addItem($0) }
            item.submenu = menu
            return menu
        }
        func item(
            _ title: String, _ action: Selector, _ key: String = "",
            target: AnyObject? = nil, mods: NSEvent.ModifierFlags = .command
        ) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = target
            if !key.isEmpty { i.keyEquivalentModifierMask = mods }
            return i
        }

        _ = submenu(
            "ClipShift",
            [
                item("About ClipShift", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
                .separator(),
                item("Settings…", #selector(showSettings), ",", target: self),
                .separator(),
                item("Hide ClipShift", #selector(NSApplication.hide(_:)), "h"),
                item(
                    "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                    mods: [.command, .option]),
                item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
                .separator(),
                item("Quit ClipShift", #selector(NSApplication.terminate(_:)), "q"),
            ])

        _ = submenu(
            "File",
            [
                item("Add Files…", #selector(openFiles), "o", target: self),
                .separator(),
                item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
            ])

        _ = submenu(
            "Edit",
            [
                item("Cut", #selector(NSText.cut(_:)), "x"),
                item("Copy", #selector(NSText.copy(_:)), "c"),
                item("Paste", #selector(NSText.paste(_:)), "v"),
                item("Select All", #selector(NSText.selectAll(_:)), "a"),
            ])

        let windowMenu = submenu(
            "Window",
            [
                item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
                item("Zoom", #selector(NSWindow.performZoom(_:))),
                .separator(),
                item("ClipShift", #selector(showMainWindowAction), "0", target: self),
            ])

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showMainWindowAction() { showMainWindow() }
}
