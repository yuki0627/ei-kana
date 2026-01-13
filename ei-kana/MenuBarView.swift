import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: KeyboardMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("有効", isOn: $monitor.isEnabled)
                .toggleStyle(.switch)

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 150)
    }
}
