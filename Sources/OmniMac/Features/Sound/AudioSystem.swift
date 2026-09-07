import AudioToolbox
import CoreAudio
import Foundation

/// Acceso a CoreAudio: dispositivos de entrada y salida, volumen, balance, silencio y avisos de cambio.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
}

/// Acceso a CoreAudio: dispositivos, salida/entrada por defecto, volumen, balance y
/// silencio. Sin drivers ni APIs privadas: lo mismo que Ajustes del Sistema › Sonido.
enum AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: Dispositivos

    static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let output = streamCount(id, kAudioObjectPropertyScopeOutput) > 0
            let input = streamCount(id, kAudioObjectPropertyScopeInput) > 0
            guard output || input, let name = name(of: id) else { return nil }
            return AudioDevice(id: id, name: name, hasOutput: output, hasInput: input)
        }
    }

    private static func streamCount(_ device: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// Identificador estable del dispositivo. El `AudioDeviceID` cambia cada vez que
    /// se reconecta, así que para recordar preferencias hay que guardar esto.
    static func uid(of device: AudioDeviceID) -> String? {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? value as String : nil
    }

    /// ¿Es un aparato del propio Mac (altavoces o micrófono internos)? Sirve para
    /// que en la lista de prioridad queden los últimos, que es su papel natural: lo
    /// que se conecta manda y ellos son el recambio.
    static func isBuiltIn(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value == kAudioDeviceTransportTypeBuiltIn
    }

    static func name(of device: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? (name as String) : nil
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func setDefaultDevice(_ id: AudioDeviceID, input: Bool) {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    // MARK: Volumen (0–1), balance y silencio

    static func volume(of device: AudioDeviceID, input: Bool) -> Float? {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        if let value = readFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, kAudioObjectPropertyElementMain) {
            return value
        }
        if let value = readFloat(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) {
            return value
        }
        let channels = [1, 2].compactMap { readFloat(device, kAudioDevicePropertyVolumeScalar, scope, AudioObjectPropertyElement($0)) }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }

    static func setVolume(_ value: Float, of device: AudioDeviceID, input: Bool) {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let clamped = min(1, max(0, value))
        if writeFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, kAudioObjectPropertyElementMain, clamped) { return }
        if writeFloat(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain, clamped) { return }
        for channel in 1...2 {
            _ = writeFloat(device, kAudioDevicePropertyVolumeScalar, scope, AudioObjectPropertyElement(channel), clamped)
        }
    }

    /// 0 = izquierda, 0,5 = centro, 1 = derecha. nil si el dispositivo no lo admite.
    static func balance(of device: AudioDeviceID) -> Float? {
        readFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain)
    }

    @discardableResult
    static func setBalance(_ value: Float, of device: AudioDeviceID) -> Bool {
        writeFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain, min(1, max(0, value)))
    }

    static func isMuted(_ device: AudioDeviceID, input: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool, _ device: AudioDeviceID, input: Bool) {
        var addr = address(kAudioDevicePropertyMute, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func readFloat(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                  _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement) -> Float? {
        var addr = address(selector, scope, element)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func writeFloat(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                   _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement, _ value: Float) -> Bool {
        var addr = address(selector, scope, element)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(value)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    // MARK: Avisos de cambio (dispositivo por defecto y lista de dispositivos)

    private static var listener: AudioObjectPropertyListenerBlock?
    private static let observedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDevices,
    ]

    static func startObserving(_ handler: @escaping () -> Void) {
        stopObserving()
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        listener = block
        for selector in observedSelectors {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        }
    }

    static func stopObserving() {
        guard let block = listener else { return }
        for selector in observedSelectors {
            var addr = address(selector)
            AudioObjectRemovePropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        }
        listener = nil
    }

    // MARK: Avisos de volumen y silencio (para que el notch se mueva con las teclas)

    private static var levelListener: AudioObjectPropertyListenerBlock?
    private static var levelSubscriptions: [(device: AudioDeviceID, address: AudioObjectPropertyAddress)] = []

    /// Escucha volumen y silencio de la salida y la entrada actuales.
    static func startObservingLevels(output: AudioDeviceID?, input: AudioDeviceID?, handler: @escaping () -> Void) {
        stopObservingLevels()
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyVolumeScalar,
            kAudioDevicePropertyMute,
        ]
        let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]
        for (device, scope) in [(output, kAudioObjectPropertyScopeOutput), (input, kAudioObjectPropertyScopeInput)] {
            guard let device else { continue }
            for selector in selectors {
                for element in elements {
                    var addr = address(selector, scope, element)
                    guard AudioObjectHasProperty(device, &addr) else { continue }
                    AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main, block)
                    levelSubscriptions.append((device, addr))
                }
            }
        }
        levelListener = block
    }

    static func stopObservingLevels() {
        guard let block = levelListener else { return }
        for subscription in levelSubscriptions {
            var addr = subscription.address
            AudioObjectRemovePropertyListenerBlock(subscription.device, &addr, DispatchQueue.main, block)
        }
        levelSubscriptions = []
        levelListener = nil
    }
}
