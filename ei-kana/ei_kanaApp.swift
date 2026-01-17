import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let keyboardMonitor = KeyboardMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor.start()
    }
}

@main
struct EiKanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: appDelegate.keyboardMonitor)
        } label: {
            Text("⌘")
        }
        .menuBarExtraStyle(.window)
    }
}
