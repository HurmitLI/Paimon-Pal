import Combine
import CoreAudio
import Foundation
import IOKit.ps
import SwiftUI

struct PowerSnapshot {
    let percentage: Int?
    let isCharging: Bool?
    let powerSource: String
    let timeRemainingMinutes: Int?
    let timeDescriptionTitle: String
}

struct SystemCapabilitySnapshot {
    let power: PowerSnapshot?
    let outputVolume: Float?
    let brightnessConclusion: String
    let notes: [String]
}

enum SystemCapabilityProbe {
    static func read() -> SystemCapabilitySnapshot {
        var notes: [String] = []
        let power = readPower()
        if power == nil { notes.append("IOKit 未返回电源信息") }

        let volume = readOutputVolume()
        if volume == nil { notes.append("CoreAudio 未返回默认输出设备音量") }

        return SystemCapabilitySnapshot(
            power: power,
            outputVolume: volume,
            brightnessConclusion: "macOS 没有面向普通第三方 App 的稳定公开屏幕亮度读写 API；本阶段不采用私有接口。",
            notes: notes
        )
    }

    private static func readPower() -> PowerSnapshot? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let percentage: Int?
            if let current, let maximum, maximum > 0 {
                percentage = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percentage = nil
            }

            let sourceState = description[kIOPSPowerSourceStateKey] as? String ?? "未知"
            let charging = description[kIOPSIsChargingKey] as? Bool
            let timeDescriptionTitle = charging == true ? "预计充满" : "预计可用"
            let timeKey = charging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let rawTime = description[timeKey] as? Int
            let time = rawTime.flatMap { $0 > 0 ? $0 : nil }

            return PowerSnapshot(
                percentage: percentage,
                isCharging: charging,
                powerSource: sourceState,
                timeRemainingMinutes: time,
                timeDescriptionTitle: timeDescriptionTitle
            )
        }
        return nil
    }

    private static func readOutputVolume() -> Float? {
        var defaultDevice = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &propertySize,
            &defaultDevice
        ) == noErr, defaultDevice != kAudioObjectUnknown else {
            return nil
        }

        var volume = Float32(0)
        propertySize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(defaultDevice, &volumeAddress),
              AudioObjectGetPropertyData(
                defaultDevice,
                &volumeAddress,
                0,
                nil,
                &propertySize,
                &volume
              ) == noErr else {
            return nil
        }
        return volume
    }
}

@MainActor
final class SystemCapabilityLabModel: ObservableObject {
    @Published private(set) var snapshot: SystemCapabilitySnapshot?

    func refresh() {
        snapshot = SystemCapabilityProbe.read()
    }
}

struct SystemCapabilityLabView: View {
    @StateObject private var model = SystemCapabilityLabModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("读取系统状态") { model.refresh() }
                .buttonStyle(.borderedProminent)

            if let snapshot = model.snapshot {
                if let power = snapshot.power {
                    Text("电量：\(power.percentage.map { "\($0)%" } ?? "未知")")
                    Text("充电：\(power.isCharging.map { $0 ? "是" : "否" } ?? "未知")")
                    Text("电源：\(power.powerSource)")
                    Text("\(power.timeDescriptionTitle)：\(power.timeRemainingMinutes.map { "\($0) 分钟" } ?? "系统未提供")")
                } else {
                    Text("电池：读取失败")
                }
                Text("输出音量：\(snapshot.outputVolume.map { "\(Int(($0 * 100).rounded()))%" } ?? "当前设备未提供主音量")")
                Divider()
                Text("亮度边界：有限通过")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(snapshot.brightnessConclusion)
                    .foregroundStyle(.secondary)
                ForEach(snapshot.notes, id: \.self) { Text($0).foregroundStyle(.red) }
            }
        }
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}
