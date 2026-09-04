import CoreAudio
import Foundation

/// Silencia el micrófono (dispositivo de entrada por defecto) con CoreAudio.
/// No captura audio: no hace falta el permiso de micrófono.
enum MicrophoneMute {
    private static func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioObjectPropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioObjectPropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var isMuted: Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = muteAddress
        if AudioObjectHasProperty(device, &address) {
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value != 0
            }
        }
        // Sin propiedad "mute": consideramos silenciado si el volumen de entrada es 0.
        var volume = volumeAddress
        var level = Float32(1)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &volume),
           AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &level) == noErr {
            return level <= 0.001
        }
        return false
    }

    /// Devuelve el estado final.
    @discardableResult
    static func set(muted: Bool) -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = muteAddress
        var settable = DarwinBoolean(false)
        if AudioObjectHasProperty(device, &address),
           AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue {
            var value: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else {
            var volume = volumeAddress
            var level: Float32 = muted ? 0 : 1
            AudioObjectSetPropertyData(device, &volume, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        }
        return isMuted
    }
}
