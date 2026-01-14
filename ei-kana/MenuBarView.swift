import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var monitor: KeyboardMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("有効")
                Spacer()
                Toggle("", isOn: $monitor.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text("ログイン時に起動")
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
