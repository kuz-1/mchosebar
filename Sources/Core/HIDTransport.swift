import Foundation
import IOKit.hid

@MainActor
final class HIDTransport {
    enum TransportError: LocalizedError {
        case notConnected, openFailed(IOReturn), sendFailed(IOReturn), timeout(String), busy, packetLost(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Dongle not connected"
            case .openFailed(let r): return String(format: "Could not open the device (0x%08x). Is Input Monitoring allowed?", r)
            case .sendFailed(let r): return String(format: "Send failed (0x%08x)", r)
            case .timeout(let what): return "Timeout: \(what)"
            case .busy: return "Another command is in progress"
            case .packetLost(let what): return "Packets lost: \(what)"
            }
        }
    }

    var log: (String) -> Void = { print($0) }
    var onConnectionChange: ((Bool) -> Void)?
    private(set) var isConnected = false

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var listener: (([UInt8]) -> Void)?
    private var commandInFlight = false

    init() {
        // dongle also shows up as a keyboard, so this needs Input Monitoring
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: MchoseProtocol.vendorID,
            kIOHIDProductIDKey: MchoseProtocol.productID,
            kIOHIDPrimaryUsagePageKey: MchoseProtocol.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.attach(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.detach(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ dev: IOHIDDevice) {
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            log(TransportError.openFailed(r).localizedDescription)
            return
        }
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, reportID, report, len in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: len))
            MainActor.assumeIsolated { me.handleInput(reportID: UInt8(truncatingIfNeeded: reportID), bytes) }
        }, ctx)
        isConnected = true
        log("Connected: \(IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?")")
        onConnectionChange?(true)
    }

    private func detach(_ dev: IOHIDDevice) {
        guard dev == device else { return }
        device = nil
        isConnected = false
        log("Disconnected")
        onConnectionChange?(false)
    }

    private func handleInput(reportID: UInt8, _ raw: [UInt8]) {
        log("RX " + hex(raw))
        guard reportID == MchoseProtocol.reportID else { return }
        // sometimes the report ID is still in front
        let d = (raw.first == MchoseProtocol.reportID && raw.count > MchoseProtocol.packetLen) ? Array(raw.dropFirst()) : raw
        listener?(d)
    }

    private func send(_ report: [UInt8]) throws {
        guard let device else { throw TransportError.notConnected }
        log("TX " + hex(report))
        let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        if r != kIOReturnSuccess { throw TransportError.sendFailed(r) }
    }

    private func sendAndAwait<T>(_ report: [UInt8], timeout: TimeInterval, what: String,
                                 _ accept: @escaping ([UInt8]) throws -> T?) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            var done = false
            var timer: Timer?
            let finish: (Result<T, Error>) -> Void = { [weak self] r in
                guard !done else { return }
                done = true
                timer?.invalidate()
                self?.listener = nil
                cont.resume(with: r)
            }
            listener = { d in
                do { if let v = try accept(d) { finish(.success(v)) } } catch { finish(.failure(error)) }
            }
            timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                MainActor.assumeIsolated { finish(.failure(TransportError.timeout(what))) }
            }
            do { try send(report) } catch { finish(.failure(error)) }
        }
    }

    private func exclusive<T>(_ body: () async throws -> T) async throws -> T {
        guard isConnected else { throw TransportError.notConnected }
        guard !commandInFlight else { throw TransportError.busy }
        commandInFlight = true
        defer { commandInFlight = false }
        return try await body()
    }

    // 2.4G drops a packet now and then, so keep what arrived and ask again
    func read(_ cmd: MchoseProtocol.Read, timeout: TimeInterval = 3, attempts: Int = 5) async throws -> [UInt8] {
        try await exclusive {
            let c = cmd.rawValue
            let what = String(format: "read 0x%02x", c)
            var chunks = [Int: [UInt8]]()
            var total: Int?
            let isComplete = { total.map { t in (0..<t).allSatisfy { chunks[$0] != nil } } ?? false }

            for attempt in 1...attempts {
                do {
                    _ = try await self.sendAndAwait(MchoseProtocol.readRequest(c), timeout: timeout, what: what) { d -> Bool? in
                        guard d.count >= 5, d[0] == c else { return nil }
                        let t = Int(d[1]), seq = Int(d[2])
                        total = t
                        chunks[seq] = Array(d[4..<(4 + min(Int(d[3]), d.count - 5))])
                        return (seq == t - 1 || isComplete()) ? true : nil
                    }
                } catch TransportError.timeout(_) {
                    // retry
                }
                if isComplete(), let total {
                    if attempt > 1 { self.log("\(what): assembled over \(attempt) attempts") }
                    return (0..<total).flatMap { chunks[$0]! }
                }
                if let total {
                    self.log("\(what) attempt \(attempt): missing packets \((0..<total).filter { chunks[$0] == nil })")
                } else {
                    self.log("\(what) attempt \(attempt): no reply")
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            throw TransportError.packetLost(what)
        }
    }

    func write(_ cmd: MchoseProtocol.Write, payload: [UInt8]) async throws {
        try await exclusive {
            let c = cmd.rawValue
            for (idx, packet) in MchoseProtocol.writePackets(c, payload: payload).enumerated() {
                var lastError: Error?
                for attempt in 1...3 {
                    do {
                        _ = try await self.sendAndAwait(packet, timeout: 2, what: String(format: "ACK 0x%02x #%d", c, idx)) { d in
                            (d.count >= 3 && d[0] == c && Int(d[2]) == idx) ? true : nil
                        }
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        log("packet #\(idx) attempt \(attempt) failed: \(error.localizedDescription)")
                    }
                }
                if let lastError { throw lastError }
            }
        }
    }
}
