import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: KeyboardController
    let onBack: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }

            SectionHeader(title: "General")
            Card {
                SettingRow(icon: "power", title: "Launch at login") {
                    switchToggle(controller.launchAtLogin) { controller.setLaunchAtLogin($0) }
                }
                SettingRow(icon: "bell.badge", title: "Low battery alerts") {
                    switchToggle(controller.lowBatteryAlerts) { controller.lowBatteryAlerts = $0 }
                }
            }

            SectionHeader(title: "Diagnostics")
            Card {
                SettingRow(icon: "doc.on.doc", title: copied ? "Copied" : "Copy log") {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Log.lines.joined(separator: "\n"), forType: .string)
                        copied = true
                    }
                    .controlSize(.mini)
                }
                SettingRow(icon: "doc.text.magnifyingglass", title: "Log file") {
                    Button("Open") { NSWorkspace.shared.open(Log.url) }.controlSize(.mini)
                }
            }

            Text("Battery is checked every \(Int(KeyboardController.batteryPollInterval / 60)) min. Alerts at \(KeyboardController.lowBatteryThresholds.map { "\($0)%" }.joined(separator: " and ")).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    private func switchToggle(_ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: set)).toggleStyle(.switch).controlSize(.mini).labelsHidden()
    }
}
