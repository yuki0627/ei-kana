import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var monitor: KeyboardMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var inputSources: [InputSourceInfo] = []

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

            VStack(alignment: .leading, spacing: 4) {
                Text("英数（左⌘）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $monitor.englishInputSourceID) {
                    ForEach(inputSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("かな（右⌘）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $monitor.japaneseInputSourceID) {
                    ForEach(inputSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
            }

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .fixedSize()
        .onAppear {
            inputSources = monitor.getSelectableInputSources()
        }
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
