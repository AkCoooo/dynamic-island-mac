import CoreAudio
import Foundation

/// Affiche le volume de la sortie audio par défaut dans l'île quand il change.
///
/// Lit Core Audio (API publique, sans permission). Le HUD système de macOS reste visible :
/// le masquer demanderait d'intercepter les touches de volume (permission Accessibilité).
final class VolumeMonitor {
    private let model: NotchModel
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listeningElements: [AudioObjectPropertyElement] = []
    private let startedAt = Date()
    private var lastShown: (Float, Bool)?

    private lazy var changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
    private lazy var deviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice() }

    init(model: NotchModel) {
        self.model = model
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceChanged)
        attachToDefaultDevice()
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func attachToDefaultDevice() {
        // Détache l'ancien appareil.
        for element in listeningElements {
            var a = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
            AudioObjectRemovePropertyListenerBlock(device, &a, .main, changed)
        }
        var mute = Self.address(kAudioDevicePropertyMute)
        if device != kAudioObjectUnknown { AudioObjectRemovePropertyListenerBlock(device, &mute, .main, changed) }
        listeningElements = []

        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr
        else { return }
        device = id

        // Certains appareils n'ont qu'un volume par canal (éléments 1 et 2).
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var v = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
            if AudioObjectHasProperty(device, &v) {
                AudioObjectAddPropertyListenerBlock(device, &v, .main, changed)
                listeningElements.append(element)
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        if AudioObjectHasProperty(device, &mute) {
            AudioObjectAddPropertyListenerBlock(device, &mute, .main, changed)
        }
        lastShown = read()
    }

    private func read() -> (Float, Bool)? {
        guard let element = listeningElements.first else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &volume) == noErr else { return nil }

        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var m = Self.address(kAudioDevicePropertyMute)
        if AudioObjectHasProperty(device, &m) { AudioObjectGetPropertyData(device, &m, 0, nil, &size, &muted) }
        return (volume, muted != 0)
    }

    private func volumeChanged() {
        guard AppSettings.shared.volumeHUD, Date().timeIntervalSince(startedAt) > 2,
              let (volume, muted) = read() else { return }
        // Les éléments 1 et 2 notifient chacun : on ignore les doublons.
        if let last = lastShown, abs(last.0 - volume) < 0.001, last.1 == muted { return }
        lastShown = (volume, muted)
        model.show(.volume(level: volume, muted: muted), for: 1.6)
    }
}
