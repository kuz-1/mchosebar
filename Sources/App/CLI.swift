import Combine
import Foundation

@MainActor
func runCLI(_ args: [String]) -> Never {
    if args.contains("--selftest") { runSelfTest() }
    let transport = HIDTransport()
    transport.log = Log.write
    var started = false

    let run = {
        guard !started else { return }
        started = true
        Task { @MainActor in
            do {
                if let i = args.firstIndex(of: "--read"), i + 1 < args.count,
                   let c = UInt8(args[i + 1], radix: 16), let cmd = MchoseProtocol.Read(rawValue: c) {
                    let b = try await transport.read(cmd)
                    print("payload \(b.count)B:")
                    stride(from: 0, to: b.count, by: 16).forEach {
                        print(String(format: "%04x  ", $0) + hex(Array(b[$0..<min($0 + 16, b.count)])))
                    }
                } else {
                    if let bat = Battery(try await transport.read(.battery)) {
                        print("Battery: \(bat.level)%\(bat.isCharging ? " (charging)" : "")  full=\(bat.fullStatus)")
                    }
                    if let p = Performance(try await transport.read(.performance)) {
                        print(KeyboardController.describe(p).joined(separator: "\n"))
                    }
                }
                exit(0)
            } catch {
                print("ERROR: \(error.localizedDescription)")
                exit(1)
            }
        }
    }
    transport.onConnectionChange = { if $0 { run() } }
    if transport.isConnected { run() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("ERROR: timeout"); exit(2) }
    RunLoop.main.run()
    exit(0)
}

// writes settings back unchanged, changes sleep time and restores it
@MainActor
func runSelfTest() -> Never {
    let c = KeyboardController()
    var started = false
    let step: (String, Task<Void, Never>) async -> Bool = { name, task in
        await task.value
        if let e = c.lastError { print("FAIL \(name): \(e)"); return false }
        print("OK   \(name)")
        return true
    }
    let run = {
        guard !started else { return }
        started = true
        Task { @MainActor in
            guard await step("read", c.refresh()), let p = c.performance, c.lightColors != nil else { exit(1) }
            let originalSleep = p.sleepMinutes
            guard await step("rewrite performance (unchanged)", c.updatePerformance { _ in }) else { exit(1) }
            guard await step("sleep -> 3.5 min", c.setSleepMinutes(3.5)), c.performance?.sleepMinutes == 3.5 else { exit(1) }
            guard await step("sleep restore", c.setSleepMinutes(originalSleep)), c.performance?.sleepMinutes == originalSleep else { exit(1) }
            let colorBefore = c.lightColors
            guard let effect = c.performance?.effect, let color = colorBefore?.color(effect),
                  await step("rewrite color (unchanged \(color.hex))", c.setColor(color)), c.lightColors == colorBefore else { exit(1) }
            print("ALL OK")
            exit(0)
        }
    }
    c.objectWillChange.sink { _ in DispatchQueue.main.async { if c.isConnected { run() } } }.store(in: &selfTestBag)
    DispatchQueue.main.asyncAfter(deadline: .now() + 40) { print("ERROR: timeout"); exit(2) }
    RunLoop.main.run()
    exit(0)
}

@MainActor var selfTestBag = Set<AnyCancellable>()
