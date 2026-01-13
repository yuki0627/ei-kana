import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var keyboardMonitor: KeyboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor?.start()
    }
}

@main
struct EiKanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var keyboardMonitor = KeyboardMonitor()

    init() {
        // KeyboardMonitor will be started via AppDelegate
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: keyboardMonitor)
                .onAppear {
                    appDelegate.keyboardMonitor = keyboardMonitor
                    keyboardMonitor.start()
                }
        } label: {
            Text("⌘")
        }
        .menuBarExtraStyle(.window)
    }
}
