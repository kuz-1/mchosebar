import SwiftUI

struct PanelView: View {
    @ObservedObject var controller: KeyboardController
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(controller: controller) { showSettings = false }
            } else {
                main
            }
        }
        .padding(10)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.15), value: showSettings)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !controller.isConnected {
                disconnected
            } else if let p = controller.performance {
                batterySection(p)
                lightingSection(p)
            } else {
                loading
            }
            HStack(spacing: 8) {
                FooterButton(title: "Settings", icon: "gearshape") { showSettings = true }
                FooterButton(title: "Quit", icon: "power") { NSApp.terminate(nil) }
            }
            .padding(.top, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("MCHOSE G75 Pro").font(.system(size: 13, weight: .semibold))
            Spacer()
            if controller.isBusy { ProgressView().controlSize(.mini) }
            Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                .buttonStyle(.borderless)
                .disabled(!controller.isConnected || controller.isBusy)
                .help("Refresh")
        }
        .overlay(alignment: .bottom) {
            if let err = controller.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, controller.lastError == nil ? 0 : 20)
    }

    private var disconnected: some View {
        Card {
            VStack(spacing: 6) {
                Image(systemName: "cable.connector.slash").font(.system(size: 18)).foregroundStyle(.secondary)
                Text("Dongle not connected").font(.system(size: 12, weight: .medium))
                Text("Plug in the 2.4G dongle or check the Input Monitoring permission.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var loading: some View {
        Card {
            HStack { Spacer(); ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary); Spacer() }
                .frame(height: 48)
        }
    }

    private func batterySection(_ p: Performance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Battery & connection") {
                HStack(spacing: 4) {
                    if controller.battery?.isCharging == true {
                        Pill(text: "Charging", icon: "bolt.fill", color: .green)
                    }
                    Pill(text: "Active", dot: true, color: .green)
                }
            }
            Card {
                batteryRow
                SettingRow(icon: "gauge.with.dots.needle.67percent", title: "Polling rate") {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).font(.system(size: 10))
                    SegmentPicker(options: PollingRate.allCases, selection: p.pollingRate,
                                  label: { $0 == .hz1000 ? "1000Hz" : "\($0.hz)" }) { controller.setPollingRate($0) }
                }
                SettingRow(icon: "laptopcomputer", title: "Mac mode") {
                    toggle(p.isMacMode) { controller.setMacMode($0) }
                }
                SettingRow(icon: "lock", title: "Win lock") {
                    toggle(p.isWinLocked) { controller.setWinLock($0) }.disabled(p.isMacMode)
                }
                .help(p.isMacMode ? "Win lock is unavailable in Mac mode" : "")
                SettingRow(icon: "speedometer", title: "Low latency") {
                    toggle(p.isLowLatency) { controller.setLowLatency($0) }
                }
                SleepRow(minutes: p.sleepMinutes) { controller.setSleepMinutes($0) }
            }
        }
    }

    private var batteryRow: some View {
        HStack(spacing: 7) {
            let level = controller.battery?.level ?? 0
            Image(systemName: batteryIcon(level))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .frame(width: 15)
            Text("Battery").font(.system(size: 12))
            BatteryBar(level: level).padding(.horizontal, 4)
            Text(controller.battery.map { "\($0.level)%" } ?? "–")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(minHeight: Theme.rowHeight)
    }

    private func batteryIcon(_ level: Int) -> String {
        if controller.battery?.isCharging == true { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func lightingSection(_ p: Performance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Effects & colors")
            Card {
                SettingRow(title: "Lighting effect") {
                    Picker("", selection: Binding(get: { p.effect ?? .off }, set: { controller.setEffect($0) })) {
                        ForEach(LightEffect.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                if let e = p.effect {
                    if e.supportsBrightness, let b = p.brightness(e) {
                        SettingRow(title: "Brightness") {
                            iconSlider(low: "sun.min", high: "sun.max", value: b, range: Performance.brightnessRange) {
                                controller.setBrightness($0)
                            }
                        }
                    }
                    if e.supportsSpeed, let s = p.speed(e) {
                        SettingRow(title: "Speed") {
                            iconSlider(low: "tortoise", high: "hare", value: s, range: Performance.speedRange) {
                                controller.setSpeed($0)
                            }
                        }
                    }
                    if e.supportsColor, let color = controller.lightColors?.color(e) {
                        ColorRow(color: color, isMulti: p.isMultiColor(e) ?? false,
                                 multiAvailable: e.supportsMultiColor,
                                 onColor: { controller.setColor($0) },
                                 onMulti: { controller.setMultiColor($0) })
                    }
                }
            }
        }
    }

    private func iconSlider(low: String, high: String, value: UInt8, range: ClosedRange<UInt8>,
                            onCommit: @escaping (UInt8) -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: low).font(.system(size: 9)).foregroundStyle(.secondary)
            CommitSlider(value: Double(value), range: Double(range.lowerBound)...Double(range.upperBound)) {
                onCommit(UInt8($0.rounded()))
            }
            .frame(width: 120)
            Image(systemName: high).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: set))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}

struct SleepRow: View {
    let minutes: Double?
    let onChange: (Double?) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 4) {
            SettingRow(icon: "moon.zzz", title: "Sleep") {
                CommitSlider(value: minutes ?? 0.5, range: 0.5...20, step: 0.5) { onChange($0) }
                    .frame(width: 110)
                    .disabled(minutes == nil)
                    .opacity(minutes == nil ? 0.4 : 1)
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if expanded {
                HStack {
                    Text(minutes.map { "Sleeps after \($0.formatted()) min" } ?? "Never sleeps")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Toggle("Never", isOn: Binding(get: { minutes == nil }, set: { onChange($0 ? nil : 3) }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: expanded)
    }
}
