import CoreAudio
import Foundation
import IOKit.ps

protocol SystemStatusReading {
    func readBattery() -> BatteryStatusSnapshot?
    func readAudio() -> AudioStatusSnapshot?
}

struct LiveSystemStatusReader: SystemStatusReading {
    func readBattery() -> BatteryStatusSnapshot? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let level: Double?
            if let current, let maximum, maximum > 0 {
                level = Double(current) / Double(maximum)
            } else {
                level = nil
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let connection: PowerConnection
            switch state {
            case kIOPSACPowerValue:
                connection = .acPower
            case kIOPSBatteryPowerValue:
                connection = .batteryPower
            default:
                connection = .unknown
            }

            return BatteryStatusSnapshot(
                level: level,
                isCharging: description[kIOPSIsChargingKey] as? Bool,
                connection: connection
            )
        }
        return nil
    }

    func readAudio() -> AudioStatusSnapshot? {
        guard let device = defaultOutputDevice() else { return nil }
        let volume = readMasterVolume(device: device) ?? readAverageChannelVolume(device: device)
        let muted = readMute(device: device)
        guard volume != nil || muted != nil else { return nil }
        return AudioStatusSnapshot(volume: volume.map(Double.init), isMuted: muted)
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr,
        device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func readMasterVolume(device: AudioDeviceID) -> Float32? {
        readFloatProperty(
            device: device,
            selector: kAudioDevicePropertyVolumeScalar,
            element: kAudioObjectPropertyElementMain
        )
    }

    private func readAverageChannelVolume(device: AudioDeviceID) -> Float32? {
        let channels = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        let values = channels.compactMap {
            readFloatProperty(device: device, selector: kAudioDevicePropertyVolumeScalar, element: $0)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float32(values.count)
    }

    private func readFloatProperty(
        device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }

    private func readMute(device: AudioDeviceID) -> Bool? {
        let elements = [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2)
        ]
        var readableValues: [Bool] = []
        for element in elements {
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                readableValues.append(value != 0)
            }
        }
        guard !readableValues.isEmpty else { return nil }
        return readableValues.contains(true)
    }
}
