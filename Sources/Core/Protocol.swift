import Foundation

// report 0x13, 19 bytes
// read:   [cmd, 01, 0..., sum]
// packet: [cmd, total, seq, len, 14 bytes, sum]
// sum = low byte of everything before it, report ID included
enum MchoseProtocol {
    static let vendorID = 0x41E4
    static let productID = 0x2001
    static let usagePage = 0xFF02
    static let reportID: UInt8 = 0x13
    static let packetLen = 19
    static let chunkLen = 14

    enum Read: UInt8 {
        case keySetting = 0x41, diyLight = 0x42, macro = 0x43, performance = 0x44, lightColor = 0x49, battery = 0x4a
    }

    enum Write: UInt8 {
        case keySetting = 0x01, diyLight = 0x02, macro = 0x03, performance = 0x04, reset = 0x06, lightColor = 0x09
    }

    static func readRequest(_ cmd: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetLen + 1)
        p[0] = reportID
        p[1] = cmd
        p[2] = 0x01
        p[packetLen] = checksum(p[0..<packetLen])
        return p
    }

    static func writePackets(_ cmd: UInt8, payload: [UInt8]) -> [[UInt8]] {
        let chunks = stride(from: 0, to: payload.count, by: chunkLen).map {
            Array(payload[$0..<min($0 + chunkLen, payload.count)])
        }
        return chunks.enumerated().map { idx, chunk in
            var len = chunk.count
            // color writes don't count trailing zeros in the last packet
            if cmd == Write.lightColor.rawValue, idx == chunks.count - 1 {
                len = chunk.lastIndex(where: { $0 != 0 }).map { $0 + 1 } ?? 0
            }
            var p = [reportID, cmd, UInt8(chunks.count), UInt8(idx), UInt8(len)] + chunk
            p += [UInt8](repeating: 0, count: packetLen - p.count)
            p.append(checksum(p[...]))
            return p
        }
    }

    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) })
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
