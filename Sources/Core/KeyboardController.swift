import Combine
import Foundation
import ServiceManagement
@preconcurrency import UserNotifications

@MainActor
final class KeyboardController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var battery: Battery?
    @Published private(set) var performance: Performance?
    @Published private(set) var lightColors: LightColors?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lowBatteryAlerts: Bool {
        didSet { UserDefaults.standard.set(lowBatteryAlerts, forKey: "lowBatteryAlerts") }
    }

    static let batteryPollInterval: TimeInterval = 5 * 60
    static let lowBatteryThresholds = [20, 10]

    private let transport: HIDTransport
    private var queueTail: Task<Void, Never>?
    private var batteryTimer: Timer?
    private var notifiedThreshold: Int?

    init(transport: HIDTransport? = nil) {
        let transport = transport ?? HIDTransport()
        self.transport = transport
        lowBatteryAlerts = UserDefaults.standard.object(forKey: "lowBatteryAlerts") as? Bool ?? true
        transport.log = Log.write
        transport.onConnectionChange = { [weak self] connected in self?.connectionChanged(connected) }
        if transport.isConnected { connectionChanged(true) }
    }

    @discardableResult func refresh() -> Task<Void, Never> {
        enqueue { [self] in
            battery = Battery(try await transport.read(.battery)) ?? battery
            performance = Performance(try await transport.read(.performance)) ?? performance
            lightColors = LightColors(try await transport.read(.lightColor)) ?? lightColors
            checkBattery()
        }
    }

    func refreshBattery() {
        enqueue { [self] in
            battery = Battery(try await transport.read(.battery)) ?? battery
            checkBattery()
        }
    }

    @discardableResult
    func updatePerformance(_ change: @escaping (inout Performance) -> Void) -> Task<Void, Never> {
        enqueue { [self] in
            // read first so changes made with Fn keys don't get overwritten
            guard var p = Performance(try await transport.read(.performance)) else { return }
            change(&p)
            try await transport.write(.performance, payload: p.raw)
            let confirmed = Performance(try await transport.read(.performance))
            performance = confirmed
            if confirmed != p { throw ControllerError.verifyFailed }
        }
    }

    func setPollingRate(_ r: PollingRate) { updatePerformance { $0.pollingRate = r } }
    func setMacMode(_ on: Bool) { updatePerformance { $0.isMacMode = on } }
    func setWinLock(_ on: Bool) { updatePerformance { $0.isWinLocked = on } }
    func setLowLatency(_ on: Bool) { updatePerformance { $0.isLowLatency = on } }
    @discardableResult func setSleepMinutes(_ m: Double?) -> Task<Void, Never> { updatePerformance { $0.sleepMinutes = m } }
    func setEffect(_ e: LightEffect) { updatePerformance { $0.effect = e } }

    func setBrightness(_ v: UInt8) { updatePerformance { p in p.effect.map { p.setBrightness(v, for: $0) } } }
    func setSpeed(_ v: UInt8) { updatePerformance { p in p.effect.map { p.setSpeed(v, for: $0) } } }
    func setMultiColor(_ multi: Bool) { updatePerformance { p in p.effect.map { p.setMultiColor(multi, for: $0) } } }

    @discardableResult func setColor(_ color: RGB) -> Task<Void, Never> {
        let task = enqueue { [self] in
            guard let p = Performance(try await transport.read(.performance)), let effect = p.effect,
                  var colors = LightColors(try await transport.read(.lightColor)) else { return }
            colors.setColor(color, for: effect)
            try await transport.write(.lightColor, payload: colors.raw)
            let confirmed = LightColors(try await transport.read(.lightColor))
            lightColors = confirmed
            if confirmed != colors { throw ControllerError.verifyFailed }
        }
        if performance.flatMap({ p in p.effect.flatMap { p.isMultiColor($0) } }) == true { setMultiColor(false) }
        return task
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    enum ControllerError: LocalizedError {
        case verifyFailed
        var errorDescription: String? { "Keyboard did not apply the change (read-back differs)" }
    }

    // one device command at a time
    @discardableResult
    private func enqueue(_ op: @escaping () async throws -> Void) -> Task<Void, Never> {
        let previous = queueTail
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            guard self.isConnected else {
                self.lastError = HIDTransport.TransportError.notConnected.localizedDescription
                return
            }
            self.isBusy = true
            do {
                try await op()
                self.lastError = nil
            } catch {
                Log.write("Error: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            }
            self.isBusy = false
        }
        queueTail = task
        return task
    }

    private func connectionChanged(_ connected: Bool) {
        isConnected = connected
        batteryTimer?.invalidate()
        batteryTimer = nil
        if connected {
            refresh()
            batteryTimer = Timer.scheduledTimer(withTimeInterval: Self.batteryPollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshBattery() }
            }
        } else {
            battery = nil
            performance = nil
            lightColors = nil
        }
    }

    private func checkBattery() {
        guard let battery else { return }
        if battery.isCharging || battery.level > (Self.lowBatteryThresholds.first ?? 20) + 5 {
            notifiedThreshold = nil
            return
        }
        guard lowBatteryAlerts,
              let threshold = Self.lowBatteryThresholds.last(where: { battery.level <= $0 }),
              notifiedThreshold.map({ threshold < $0 }) ?? true else { return }
        notifiedThreshold = threshold
        let level = battery.level
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Keyboard battery \(level)%"
            content.body = "MCHOSE G75 Pro is running low. Plug in the cable."
            try? await center.add(UNNotificationRequest(identifier: "lowBattery", content: content, trigger: nil))
        }
    }

    static func describe(_ p: Performance) -> [String] {
        var s = [
            "Polling rate: " + (p.pollingRate?.title ?? "?"),
            "Mode: \(p.isMacMode ? "Mac" : "Windows")",
            "Win lock: \(p.isWinLocked ? "on" : "off")",
            "Low latency: \(p.isLowLatency ? "on" : "off")",
            "Sleep: " + (p.sleepMinutes.map { "\($0.formatted()) min" } ?? "never"),
            "Effect: " + (p.effect?.title ?? "?"),
        ]
        if let e = p.effect, let b = p.brightness(e), let sp = p.speed(e), let m = p.isMultiColor(e) {
            s.append("Brightness \(b), speed \(sp), \(m ? "multi" : "single") color")
        }
        return s
    }
}
