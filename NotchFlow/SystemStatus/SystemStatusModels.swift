import Foundation

enum PowerConnection: String, Equatable {
    case acPower
    case batteryPower
    case unknown

    var displayName: String {
        switch self {
        case .acPower: "电源适配器"
        case .batteryPower: "电池"
        case .unknown: "未知"
        }
    }
}

struct BatteryStatusSnapshot: Equatable {
    let level: Double?
    let isCharging: Bool?
    let connection: PowerConnection

    init(level: Double?, isCharging: Bool?, connection: PowerConnection) {
        self.level = Self.normalized(level)
        self.isCharging = isCharging
        self.connection = connection
    }

    var percentage: Int? {
        level.map { Int(($0 * 100).rounded()) }
    }

    var isLow: Bool {
        guard let level else { return false }
        return level <= 0.20 && isCharging != true && connection != .acPower
    }

    private static func normalized(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }
}

struct AudioStatusSnapshot: Equatable {
    let volume: Double?
    let isMuted: Bool?

    init(volume: Double?, isMuted: Bool?) {
        if let volume, volume.isFinite, (0...1).contains(volume) {
            self.volume = volume
        } else {
            self.volume = nil
        }
        self.isMuted = isMuted
    }

    var percentage: Int? {
        volume.map { Int(($0 * 100).rounded()) }
    }
}

struct SystemStatusSnapshot: Equatable {
    var battery: BatteryStatusSnapshot?
    var audio: AudioStatusSnapshot?

    static let unavailable = SystemStatusSnapshot(battery: nil, audio: nil)
}

enum SystemStatusEvent: Equatable {
    case powerConnected(BatteryStatusSnapshot)
    case powerDisconnected(BatteryStatusSnapshot)
    case lowBattery(BatteryStatusSnapshot)
    case volumeChanged(AudioStatusSnapshot)
    case muteChanged(AudioStatusSnapshot)

    var activity: IslandActivity {
        switch self {
        case .powerConnected(let battery):
            return IslandActivity(
                id: "system.power",
                kind: .systemHUD,
                title: battery.percentage.map { "充电 \($0)%" } ?? "已接通电源",
                detail: "电源适配器",
                systemSymbol: "bolt.fill",
                progress: battery.level
            )
        case .powerDisconnected(let battery):
            return IslandActivity(
                id: "system.power",
                kind: .systemHUD,
                title: battery.percentage.map { "电池 \($0)%" } ?? "已使用电池",
                detail: "电源已断开",
                systemSymbol: "battery.75percent",
                progress: battery.level
            )
        case .lowBattery(let battery):
            return IslandActivity(
                id: "system.lowBattery",
                kind: .criticalSystem,
                title: battery.percentage.map { "电量低 \($0)%" } ?? "电量低",
                detail: "请连接电源",
                systemSymbol: "battery.25percent",
                progress: battery.level
            )
        case .volumeChanged(let audio):
            let percentage = audio.percentage ?? 0
            return IslandActivity(
                id: "system.audio",
                kind: .systemHUD,
                title: "音量 \(percentage)%",
                systemSymbol: Self.volumeSymbol(volume: audio.volume ?? 0),
                progress: audio.volume
            )
        case .muteChanged(let audio):
            let muted = audio.isMuted == true
            return IslandActivity(
                id: "system.audio",
                kind: .systemHUD,
                title: muted ? "已静音" : "音量 \(audio.percentage ?? 0)%",
                systemSymbol: muted ? "speaker.slash.fill" : Self.volumeSymbol(volume: audio.volume ?? 0),
                progress: muted ? 0 : audio.volume
            )
        }
    }

    var duration: Duration {
        switch self {
        case .lowBattery: .seconds(3)
        default: .milliseconds(1500)
        }
    }

    private static func volumeSymbol(volume: Double) -> String {
        switch volume {
        case ...0: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

enum SystemStatusEventResolver {
    static func powerEvents(
        previous: BatteryStatusSnapshot?,
        current: BatteryStatusSnapshot
    ) -> [SystemStatusEvent] {
        guard let previous else {
            return current.isLow ? [.lowBattery(current)] : []
        }

        var events: [SystemStatusEvent] = []
        if previous.connection != current.connection {
            switch current.connection {
            case .acPower:
                events.append(.powerConnected(current))
            case .batteryPower:
                events.append(.powerDisconnected(current))
            case .unknown:
                break
            }
        }
        if !previous.isLow, current.isLow {
            events.append(.lowBattery(current))
        }
        return events
    }

    static func audioEvents(
        previous: AudioStatusSnapshot?,
        current: AudioStatusSnapshot
    ) -> [SystemStatusEvent] {
        guard let previous else { return [] }

        if previous.isMuted != current.isMuted,
           current.isMuted != nil {
            return [.muteChanged(current)]
        }

        guard let oldVolume = previous.volume,
              let newVolume = current.volume,
              abs(oldVolume - newVolume) >= 0.005
        else { return [] }
        return [.volumeChanged(current)]
    }
}
