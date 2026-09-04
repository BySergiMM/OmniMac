import AppKit
import CoreAudio

/// Lo que enseña la tarjeta del notch al conectar unos auriculares de Apple.
struct HeadphonesInfo: Equatable {
    var name: String
    var symbol: String
    var leftSymbol: String?
    var rightSymbol: String?
    var caseSymbol: String?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var main: Int?

    var hasBattery: Bool { left != nil || right != nil || caseLevel != nil || main != nil }

    static let sample = HeadphonesInfo(name: L("AirPods Pro de Sergi", "Sergi's AirPods Pro"), symbol: "airpodspro",
                                       leftSymbol: "airpodpro.left", rightSymbol: "airpodpro.right",
                                       caseSymbol: "airpodspro.chargingcase.wireless",
                                       left: 85, right: 90, caseLevel: 62, main: nil)
}

/// Modelos de Apple y Beats: símbolo SF por identificador de producto (o por el nombre).
enum AppleHeadphones {
    static let appleVendorID = 0x004C

    static func looksApple(name: String) -> Bool {
        let n = name.lowercased()
        return ["airpods", "beats", "powerbeats", "studio buds", "fit pro", "solo buds"].contains { n.contains($0) }
    }

    /// (símbolo, izquierdo, derecho, estuche)
    static func symbols(productID: Int?, name: String) -> (String, String?, String?, String?) {
        let n = name.lowercased()
        switch productID {
        case 0x2002, 0x200F: return ok("airpods", "airpod.left", "airpod.right", "airpods.chargingcase.wireless")
        case 0x2013: return ok("airpods.gen3", "airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless")
        case 0x2019, 0x201B: return ok("airpods.gen4", "airpod.gen3.left", "airpod.gen3.right", "airpods.gen4.chargingcase.wireless")
        case 0x200E, 0x2014, 0x2024: return ok("airpodspro", "airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless")
        case 0x200A, 0x201F: return ok("airpodsmax", nil, nil, nil)
        case 0x2003: return ok("beats.powerbeats3", nil, nil, nil)
        case 0x200B: return ok("beats.powerbeatspro", nil, nil, nil)
        case 0x200D: return ok("beats.powerbeats", nil, nil, nil)
        case 0x2005, 0x2010: return ok("beats.earphones", nil, nil, nil)
        case 0x2006, 0x2009, 0x200C, 0x2017: return ok("beats.headphones", nil, nil, nil)
        case 0x2011, 0x2016: return ok("beats.studiobuds", nil, nil, "beats.studiobuds.chargingcase")
        case 0x2012: return ok("beats.fitpro", nil, nil, "beats.fitpro.chargingcase")
        default: break
        }
        if n.contains("airpods") {
            if n.contains("max") { return ok("airpodsmax", nil, nil, nil) }
            if n.contains("pro") { return ok("airpodspro", "airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless") }
            return ok("airpods.gen3", "airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless")
        }
        if n.contains("powerbeats pro") { return ok("beats.powerbeatspro", nil, nil, nil) }
        if n.contains("powerbeats") { return ok("beats.powerbeats", nil, nil, nil) }
        if n.contains("studio buds") { return ok("beats.studiobuds", nil, nil, "beats.studiobuds.chargingcase") }
        if n.contains("fit pro") { return ok("beats.fitpro", nil, nil, "beats.fitpro.chargingcase") }
        if n.contains("solo buds") { return ok("beats.solobuds", nil, nil, "beats.solobuds.chargingcase.fill") }
        if n.contains("beats") { return ok("beats.headphones", nil, nil, nil) }
        return ok("headphones", nil, nil, nil)
    }

    /// Cada símbolo se comprueba en este macOS; si no existe, uno genérico.
    private static func ok(_ s: String, _ l: String?, _ r: String?, _ c: String?) -> (String, String?, String?, String?) {
        func has(_ name: String?) -> String? {
            guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
            return name
        }
        return (has(s) ?? "headphones", has(l), has(r), has(c))
    }
}

/// Detecta cuándo se conectan unos AirPods o Beats SIN permisos: CoreAudio avisa en el
/// acto de que ha aparecido un dispositivo de audio Bluetooth. Después,
/// `system_profiler` (1–3 s) confirma que es de Apple y trae modelo y batería.
final class HeadphonesWatcher {
    /// Se llama con la tarjeta inicial (nombre y modelo) y de nuevo cuando llega la batería.
    var onConnect: ((HeadphonesInfo) -> Void)?
    var onUpdate: ((HeadphonesInfo) -> Void)?

    private var known: Set<String> = []
    private var recent: [String: Date] = [:]
    private var listening = false
    private var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }

    func start() {
        guard !listening else { return }
        listening = true
        known = Set(bluetoothDevices().map(\.uid))
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    func stop() {
        guard listening else { return }
        listening = false
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    // MARK: - Interno

    private struct BluetoothDevice { let uid: String; let name: String }

    private func devicesChanged() {
        let now = bluetoothDevices()
        let added = now.filter { !known.contains($0.uid) }
        known = Set(now.map(\.uid))
        for device in added {
            if let last = recent[device.uid], Date().timeIntervalSince(last) < 20 { continue }
            recent[device.uid] = Date()
            handleConnection(of: device)
        }
    }

    private func handleConnection(of device: BluetoothDevice) {
        let looksApple = AppleHeadphones.looksApple(name: device.name)
        if looksApple {
            let s = AppleHeadphones.symbols(productID: nil, name: device.name)
            onConnect?(HeadphonesInfo(name: device.name, symbol: s.0, leftSymbol: s.1, rightSymbol: s.2, caseSymbol: s.3))
        }
        // Fabricante, modelo y batería: system_profiler en segundo plano.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let details = Self.profile(named: device.name) else { return }
            guard details.vendorID == AppleHeadphones.appleVendorID else { return }
            let s = AppleHeadphones.symbols(productID: details.productID, name: device.name)
            let info = HeadphonesInfo(name: device.name, symbol: s.0, leftSymbol: s.1, rightSymbol: s.2, caseSymbol: s.3,
                                      left: details.left, right: details.right, caseLevel: details.caseLevel, main: details.main)
            DispatchQueue.main.async {
                if looksApple { self?.onUpdate?(info) } else { self?.onConnect?(info) }
            }
        }
    }

    private struct Details { var vendorID: Int?; var productID: Int?; var left: Int?; var right: Int?; var caseLevel: Int?; var main: Int? }

    /// `system_profiler SPBluetoothDataType -json`: busca el dispositivo conectado por nombre.
    private static func profile(named name: String) -> Details? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = section["device_connected"] as? [[String: Any]] else { return nil }
        func percent(_ value: Any?) -> Int? {
            guard let text = value as? String else { return nil }
            return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        }
        func hex(_ value: Any?) -> Int? {
            guard let text = value as? String else { return nil }
            return Int(text.replacingOccurrences(of: "0x", with: ""), radix: 16)
        }
        // Coincidencia por nombre (el de CoreAudio y el de Bluetooth coinciden en los de Apple).
        let wanted = name.lowercased()
        for entry in connected {
            for (deviceName, value) in entry {
                guard let props = value as? [String: Any] else { continue }
                let n = deviceName.lowercased()
                guard n == wanted || wanted.hasPrefix(n) || n.hasPrefix(wanted) else { continue }
                return Details(vendorID: hex(props["device_vendorID"]), productID: hex(props["device_productID"]),
                               left: percent(props["device_batteryLevelLeft"]), right: percent(props["device_batteryLevelRight"]),
                               caseLevel: percent(props["device_batteryLevelCase"]), main: percent(props["device_batteryLevelMain"]))
            }
        }
        return nil
    }

    private func bluetoothDevices() -> [BluetoothDevice] {
        var size: UInt32 = 0
        var listAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let transport: UInt32 = Self.property(id, kAudioDevicePropertyTransportType),
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  let uid: CFString = Self.property(id, kAudioDevicePropertyDeviceUID),
                  let name: CFString = Self.property(id, kAudioObjectPropertyName) else { return nil }
            return BluetoothDevice(uid: uid as String, name: name as String)
        }
    }

    private static func property<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
}
