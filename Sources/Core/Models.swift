import Foundation

enum PollingRate: UInt8, CaseIterable, Identifiable {
    case hz250 = 1, hz500 = 2, hz1000 = 3
    var id: UInt8 { rawValue }
    var hz: Int { [250, 500, 1000][Int(rawValue) - 1] }
    var title: String { "\(hz) Hz" }
}

enum LightEffect: UInt8, CaseIterable, Identifiable {
    case off = 0, alwaysOn = 1, breathing = 2, rainbow = 3, flashAway = 4, raining = 5,
         ripple = 7, stars = 8, flowingWater = 10, tidalRhythm = 11, lightAndShadow = 12,
         sineWave = 13, pinwheel = 15, waterfall = 16, flowerDance = 17, custom = 21

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .alwaysOn: return "Always on"
        case .breathing: return "Breathing"
        case .rainbow: return "Rainbow"
        case .flashAway: return "Flash away"
        case .raining: return "Raining"
        case .ripple: return "Ripple"
        case .stars: return "Stars"
        case .flowingWater: return "Flowing water"
        case .tidalRhythm: return "Tidal rhythm"
        case .lightAndShadow: return "Light & shadow"
        case .sineWave: return "Sine wave"
        case .pinwheel: return "Pinwheel"
        case .waterfall: return "Waterfall"
        case .flowerDance: return "Flower dance"
        case .custom: return "Custom (per-key)"
        }
    }

    var supportsBrightness: Bool { ![.off, .pinwheel, .flowerDance, .custom].contains(self) }
    var supportsSpeed: Bool { ![.off, .alwaysOn, .pinwheel, .flowerDance, .custom].contains(self) }
    var supportsColor: Bool { LightColors.slotOffset(self) != nil && self != .rainbow }
    var supportsMultiColor: Bool { supportsColor }
}

// 128 byte settings block. Writes send the whole block back with a few bytes changed.
struct Performance: Equatable {
    static let size = 128
    static let brightnessRange: ClosedRange<UInt8> = 1...9
    static let speedRange: ClosedRange<UInt8> = 1...4
    static let multiColorValue: UInt8 = 7

    private(set) var raw: [UInt8]

    private enum Offset {
        static let rateVal = 1, latencySwitch = 3, lightType = 9, lightMode = 10
        static let winKeySwitch = 15, sleepTimeVal = 24, macSwitch = 27
    }

    // [brightness, speed << 4 | multi]
    private static let effectSlots: [LightEffect: Int] = [
        .alwaysOn: 58, .breathing: 60, .rainbow: 62, .flashAway: 64, .raining: 66, .ripple: 70, .stars: 72,
        .flowingWater: 76, .tidalRhythm: 78, .lightAndShadow: 80, .sineWave: 82, .pinwheel: 84,
        .waterfall: 88, .flowerDance: 90,
    ]

    init?(_ bytes: [UInt8]) {
        guard bytes.count == Self.size else { return nil }
        raw = bytes
    }

    var pollingRate: PollingRate? {
        get { PollingRate(rawValue: raw[Offset.rateVal]) }
        set { if let newValue { raw[Offset.rateVal] = newValue.rawValue } }
    }

    // 2 = Mac, 0 = Windows. Mac mode also turns off Win lock.
    var isMacMode: Bool {
        get { raw[Offset.macSwitch] == 2 }
        set {
            raw[Offset.macSwitch] = newValue ? 2 : 0
            if newValue { raw[Offset.winKeySwitch] = 0 }
        }
    }

    var isWinLocked: Bool {
        get { raw[Offset.winKeySwitch] == 1 }
        set { raw[Offset.winKeySwitch] = newValue ? 1 : 0 }
    }

    // 0 = on, 2 = off
    var isLowLatency: Bool {
        get { raw[Offset.latencySwitch] == 0 }
        set { raw[Offset.latencySwitch] = newValue ? 0 : 2 }
    }

    // stored as minutes * 2, 0 = never
    var sleepMinutes: Double? {
        get { raw[Offset.sleepTimeVal] == 0 ? nil : Double(raw[Offset.sleepTimeVal]) / 2 }
        set { raw[Offset.sleepTimeVal] = newValue.map { UInt8(min(max($0, 0.5), 20) * 2) } ?? 0 }
    }

    var effect: LightEffect? {
        get { LightEffect(rawValue: raw[Offset.lightMode]) }
        set {
            guard let newValue else { return }
            raw[Offset.lightMode] = newValue.rawValue
            raw[Offset.lightType] = newValue == .custom ? 1 : 0
        }
    }

    func brightness(_ e: LightEffect) -> UInt8? { Self.effectSlots[e].map { raw[$0] } }
    func speed(_ e: LightEffect) -> UInt8? { Self.effectSlots[e].map { raw[$0 + 1] >> 4 } }
    func isMultiColor(_ e: LightEffect) -> Bool? { Self.effectSlots[e].map { raw[$0 + 1] & 0x0F == Self.multiColorValue } }

    mutating func setBrightness(_ v: UInt8, for e: LightEffect) {
        guard let o = Self.effectSlots[e] else { return }
        raw[o] = min(max(v, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
    }

    mutating func setSpeed(_ v: UInt8, for e: LightEffect) {
        guard let o = Self.effectSlots[e] else { return }
        let s = min(max(v, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        raw[o + 1] = s << 4 | (raw[o + 1] & 0x0F)
    }

    mutating func setMultiColor(_ multi: Bool, for e: LightEffect) {
        guard let o = Self.effectSlots[e] else { return }
        raw[o + 1] = (raw[o + 1] & 0xF0) | (multi ? Self.multiColorValue : 0)
    }
}

// [level, charging << 4 | full]
struct Battery: Equatable {
    let level: Int
    let isCharging: Bool
    let fullStatus: UInt8

    init?(_ b: [UInt8]) {
        guard b.count >= 2 else { return nil }
        level = Int(b[0])
        isCharging = b[1] >> 4 == 1
        fullStatus = b[1] & 0x0F
    }
}

struct RGB: Equatable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    static let presets: [(name: String, color: RGB)] = [
        ("Red", RGB(r: 255, g: 0, b: 0)), ("Orange", RGB(r: 255, g: 160, b: 0)),
        ("Yellow", RGB(r: 255, g: 255, b: 0)), ("Green", RGB(r: 0, g: 255, b: 0)),
        ("Cyan", RGB(r: 0, g: 255, b: 255)), ("Blue", RGB(r: 0, g: 0, b: 255)),
        ("Magenta", RGB(r: 255, g: 0, b: 255)), ("White", RGB(r: 255, g: 255, b: 255)),
    ]
}

// 490 byte color block, 21 bytes per effect, color is the first 3
struct LightColors: Equatable {
    static let size = 490
    static let stride = 21
    private static let colorEffects: Set<LightEffect> = [
        .alwaysOn, .breathing, .rainbow, .flashAway, .raining, .ripple, .stars,
        .flowingWater, .tidalRhythm, .lightAndShadow, .sineWave,
    ]

    private(set) var raw: [UInt8]

    init?(_ bytes: [UInt8]) {
        guard bytes.count == Self.size else { return nil }
        raw = bytes
    }

    static func slotOffset(_ e: LightEffect) -> Int? {
        colorEffects.contains(e) ? Int(e.rawValue) * stride : nil
    }

    func color(_ e: LightEffect) -> RGB? {
        Self.slotOffset(e).map { RGB(r: raw[$0], g: raw[$0 + 1], b: raw[$0 + 2]) }
    }

    mutating func setColor(_ c: RGB, for e: LightEffect) {
        guard let o = Self.slotOffset(e) else { return }
        raw[o] = c.r
        raw[o + 1] = c.g
        raw[o + 2] = c.b
    }
}
