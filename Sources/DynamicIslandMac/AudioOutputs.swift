import CoreAudio
import Foundation

struct AudioOutput: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbol: String
}

/// Liste les sorties audio et change la sortie par défaut (Core Audio, API publique).
enum AudioOutputs {
    static func all() -> [AudioOutput] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return AudioOutput(id: id, name: name, symbol: symbol(for: id, name: name))
        }
    }

    static var defaultOutput: AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    static func setDefault(_ id: AudioObjectID) {
        var device = id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &device)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func symbol(for id: AudioObjectID, name: String) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("homepod") { return "homepod.fill" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        default: return "hifispeaker.fill"
        }
    }
}
