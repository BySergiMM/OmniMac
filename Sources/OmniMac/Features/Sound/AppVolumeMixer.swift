import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio

/// Qué app "responde" de un proceso auxiliar (p. ej. el proceso de audio de Safari →
/// Safari). Misma API que usan las apps de captura de audio.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

/// Nombre de un proceso sin app (afplay, un script…): "afplay", "claude"…
@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> Int32

private func processName(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    let length = proc_name(pid, &buffer, 256)
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

struct AudioApp: Identifiable, Equatable {
    let key: String                 // bundle id de la app (o "pid:N")
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let processObjects: [AudioObjectID]
    let isPlaying: Bool
    var volume: Float               // 0–1 (1 = sin tocar)

    var id: String { key }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.key == rhs.key && lhs.isPlaying == rhs.isPlaying
            && lhs.volume == rhs.volume && lhs.processObjects == rhs.processObjects
    }
}

/// Volumen por app. Para cada app con volumen distinto del 100 % se crea un "tap"
/// de proceso (macOS 14.2+) que silencia su audio en la mezcla del sistema y nos lo
/// entrega; lo reproducimos nosotros, escalado, en la salida real mediante un
/// dispositivo agregado privado. Las apps al 100 % no se tocan (coste cero) y, si
/// OmniMac se cierra, los taps desaparecen y todo vuelve a la normalidad.
final class AppVolumeMixer: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var lastError: String?

    private var volumes: [String: Float]
    private var watchers = 0
    private var timer: Timer?
    private let engine = MixEngine()
    private var engineSignature: [String] = []
    private var engineOutput: AudioDeviceID = 0
    private var listener: AudioObjectPropertyListenerBlock?
    private static let defaultsKey = "sound.appVolumes"

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        volumes = stored.mapValues { Float($0) }
    }

    func start() {
        installListener()
        refreshApps()
    }

    func stop() {
        removeListener()
        timer?.invalidate()
        timer = nil
        engine.stop()
        engineSignature = []
    }

    /// Mientras alguna vista enseña la lista (notch o Ajustes): refresco del estado
    /// "sonando" cada 2 s. Sin vistas, solo reaccionamos a que aparezcan o
    /// desaparezcan procesos con audio (aviso de CoreAudio).
    func beginWatching() {
        watchers += 1
        refreshApps()
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshApps() }
        t.tolerance = 0.5
        timer = t
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func setVolume(_ value: Float, for app: AudioApp) {
        let clamped = min(1, max(0, value))
        if clamped >= 0.995 {
            volumes.removeValue(forKey: app.key)
        } else {
            volumes[app.key] = clamped
        }
        UserDefaults.standard.set(volumes.mapValues { Double($0) }, forKey: Self.defaultsKey)
        if let index = apps.firstIndex(where: { $0.key == app.key }) {
            apps[index].volume = clamped >= 0.995 ? 1 : clamped
        }
        syncEngine()
    }

    /// Ha cambiado la salida por defecto: el mezclador debe reproducir por la nueva.
    func outputDeviceChanged() {
        syncEngine(force: true)
    }

    func refreshApps() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        struct Group {
            var pid: pid_t
            var name: String
            var icon: NSImage?
            var objects: [AudioObjectID] = []
            var playing = false
        }
        var groups: [String: Group] = [:]
        var order: [String] = []

        for process in AudioProcesses.list() where process.pid != myPID {
            let responsible = responsibility_get_pid_responsible_for_pid(process.pid)
            let ownerPID = responsible > 0 ? responsible : process.pid
            guard ownerPID != myPID else { continue }
            let app = NSRunningApplication(processIdentifier: ownerPID)
            let key = app?.bundleIdentifier ?? process.bundleID ?? "pid:\(ownerPID)"
            let fallbackName = processName(ownerPID) ?? process.bundleID?.components(separatedBy: ".").last ?? "Proceso \(ownerPID)"
            if groups[key] == nil {
                groups[key] = Group(pid: ownerPID, name: app?.localizedName ?? fallbackName, icon: app?.icon)
                order.append(key)
            }
            groups[key]?.objects.append(process.objectID)
            if process.isRunningOutput { groups[key]?.playing = true }
        }

        var list: [AudioApp] = []
        for key in order {
            guard let group = groups[key] else { continue }
            let custom = volumes[key]
            // Solo apps que suenan ahora o que tienen volumen personalizado.
            guard group.playing || custom != nil else { continue }
            list.append(AudioApp(key: key, pid: group.pid, name: group.name, icon: group.icon,
                                 processObjects: group.objects, isPlaying: group.playing, volume: custom ?? 1))
        }
        list.sort { a, b in
            if a.isPlaying != b.isPlaying { return a.isPlaying }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        if list != apps { apps = list }
        syncEngine()
    }

    /// Un tap por app con volumen personalizado; ganancias en vivo sin reconstruir.
    private func syncEngine(force: Bool = false) {
        let output = AudioSystem.defaultDevice(input: false) ?? 0
        let tapped = apps.filter { volumes[$0.key] != nil }
        let signature = tapped.map { "\($0.key):\($0.processObjects)" }
        if !force, signature == engineSignature, output == engineOutput {
            engine.updateGains(tapped.map { volumes[$0.key] ?? 1 })
            return
        }
        engine.stop()
        engineSignature = []
        engineOutput = output
        guard !tapped.isEmpty, output != 0 else { return }
        do {
            try engine.start(groups: tapped.map { ($0.processObjects, volumes[$0.key] ?? 1) }, outputDevice: output)
            engineSignature = signature
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Toast.show("Volumen por app: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func installListener() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshApps() }
        listener = block
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    private func removeListener() {
        guard let block = listener else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        listener = nil
    }
}

// MARK: - Procesos con audio

enum AudioProcesses {
    struct Process {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let isRunningOutput: Bool
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func list() -> [Process] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var pidAddress = address(kAudioProcessPropertyPID)
            var pid = pid_t(0)
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 else { return nil }

            var runningAddress = address(kAudioProcessPropertyIsRunningOutput)
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &runningAddress, 0, nil, &runningSize, &running)

            var bundleAddress = address(kAudioProcessPropertyBundleID)
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            let bundleStatus = withUnsafeMutablePointer(to: &bundle) {
                AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, $0)
            }
            let bundleID = bundleStatus == noErr ? (bundle as String) : ""
            return Process(objectID: id, pid: pid, bundleID: bundleID.isEmpty ? nil : bundleID, isRunningOutput: running != 0)
        }
    }
}

// MARK: - Motor: taps → dispositivo agregado → salida real, con ganancia por app

final class MixEngine {
    struct EngineError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var taps: [AudioObjectID] = []
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let gains = UnsafeMutablePointer<Float>.allocate(capacity: 64)
    private static let maxTaps = 64

    deinit {
        stop()
        gains.deallocate()
    }

    func updateGains(_ values: [Float]) {
        for (index, value) in values.prefix(Self.maxTaps).enumerated() {
            gains[index] = value
        }
    }

    func start(groups: [([AudioObjectID], Float)], outputDevice: AudioDeviceID) throws {
        stop()
        guard !groups.isEmpty, groups.count <= Self.maxTaps else { return }

        var tapUIDs: [String] = []
        for (index, group) in groups.enumerated() {
            let description = CATapDescription(stereoMixdownOfProcesses: group.0)
            description.muteBehavior = .mutedWhenTapped
            description.isPrivate = true
            description.name = "OmniMac volumen por app \(index)"
            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr, tapID != kAudioObjectUnknown else {
                stop()
                throw EngineError(message: status == kAudioHardwareIllegalOperationError
                                  ? "macOS no ha dado permiso para captar el audio del sistema (Ajustes del Sistema › Privacidad › Grabación de pantalla y audio del sistema)"
                                  : "no se pudo captar el audio de la app (\(status))")
            }
            taps.append(tapID)
            gains[index] = group.1
            tapUIDs.append(try Self.string(of: tapID, selector: kAudioTapPropertyUID))
        }

        let format = try Self.format(of: taps[0])
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            stop()
            throw EngineError(message: "formato de audio no compatible")
        }
        let outputUID = try Self.string(of: outputDevice, selector: kAudioDevicePropertyDeviceUID)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OmniMac Mezclador",
            kAudioAggregateDeviceUIDKey: "com.seergiii.omnimac.mixer",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map { [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: $0] },
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            stop()
            throw EngineError(message: "no se pudo crear el mezclador (\(aggregateStatus))")
        }
        aggregate = aggregateID

        let tapCount = groups.count
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let tapChannels = max(1, Int(format.mChannelsPerFrame))
        let buffersPerTap = interleaved ? 1 : tapChannels
        let gains = self.gains
        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inputData, _, outputData, _ in
            MixEngine.mix(input: inputData, output: outputData, gains: gains, tapCount: tapCount,
                          buffersPerTap: buffersPerTap, tapChannels: tapChannels, interleaved: interleaved)
        }
        guard procStatus == noErr, let procID else {
            stop()
            throw EngineError(message: "no se pudo arrancar el mezclador (\(procStatus))")
        }
        proc = procID
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            stop()
            throw EngineError(message: "no se pudo arrancar el mezclador (\(startStatus))")
        }
    }

    func stop() {
        if aggregate != kAudioObjectUnknown {
            if let proc {
                AudioDeviceStop(aggregate, proc)
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        proc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        for tap in taps { AudioHardwareDestroyProcessTap(tap) }
        taps = []
    }

    /// Hilo de audio: sin reservas de memoria ni bloqueos. Los últimos
    /// `tapCount × buffersPerTap` búferes de entrada son los taps (si la salida
    /// tuviera entradas propias, irían antes).
    private static func mix(input: UnsafePointer<AudioBufferList>,
                            output: UnsafeMutablePointer<AudioBufferList>,
                            gains: UnsafeMutablePointer<Float>,
                            tapCount: Int, buffersPerTap: Int, tapChannels: Int, interleaved: Bool) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let tapBase = max(0, inputs.count - tapCount * buffersPerTap)
        let floatSize = MemoryLayout<Float>.size
        var globalChannel = 0
        for outBuffer in outputs {
            let outChannels = Int(outBuffer.mNumberChannels)
            guard outChannels > 0, let outData = outBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outFrames = Int(outBuffer.mDataByteSize) / (outChannels * floatSize)
            for oc in 0..<outChannels {
                let channel = globalChannel + oc
                let tapChannel = min(channel, tapChannels - 1)
                for tap in 0..<tapCount {
                    let gain = gains[tap]
                    if gain <= 0.0001 { continue }
                    let bufferIndex = tapBase + tap * buffersPerTap + (interleaved ? 0 : tapChannel)
                    guard bufferIndex < inputs.count else { continue }
                    let inBuffer = inputs[bufferIndex]
                    let inChannels = max(1, Int(inBuffer.mNumberChannels))
                    guard let inData = inBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let inFrames = Int(inBuffer.mDataByteSize) / (inChannels * floatSize)
                    let stride = interleaved ? inChannels : 1
                    let offset = interleaved ? min(tapChannel, inChannels - 1) : 0
                    let frames = min(outFrames, inFrames)
                    guard frames > 0 else { continue }
                    // out[oc] += in[canal] × ganancia, vectorizado (con saltos entre canales).
                    var scale = gain
                    vDSP_vsma(inData + offset, stride, &scale,
                              outData + oc, outChannels,
                              outData + oc, outChannels,
                              vDSP_Length(frames))
                }
            }
            globalChannel += outChannels
        }
    }

    private static func string(of object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw EngineError(message: "no se pudo leer el dispositivo (\(status))") }
        return value as String
    }

    private static func format(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard status == noErr else { throw EngineError(message: "no se pudo leer el formato del audio (\(status))") }
        return format
    }
}
