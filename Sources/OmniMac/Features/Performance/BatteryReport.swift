import Foundation
import IOKit
import IOKit.ps

/// La batería por dentro: salud, ciclos, cargador y en qué anda ahora.
///
/// Todo se lee sin privilegios. Para **controlar** la carga (pararla en un
/// porcentaje, gastar batería enchufado) haría falta escribir en el SMC como root, y
/// eso no se hace: en el M5 con macOS 27 no existe ninguna de las claves que usan las
/// apps de ese tipo, y un ayudante con privilegios no se puede proteger con la firma
/// ad hoc de la app. El límite de carga de verdad lo pone macOS (26.4 o posterior).
struct BatteryReport: Equatable {
    var percent = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    /// Minutos, o `nil` mientras macOS lo calcula (al enchufar tarda un rato).
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// Vatios del cargador, si hay uno puesto.
    var adapterWatts: Int?
    var cycleCount: Int?
    /// Ciclos para los que está diseñada (1000 en los portátiles actuales).
    var designCycleCount: Int?
    /// Capacidad de fábrica y la que tiene hoy, en mAh.
    var designCapacity: Int?
    var currentCapacity: Int?

    /// Lo que queda de la de fábrica, en %. Es la cuenta cruda: macOS redondea a su
    /// manera y por eso la cifra principal es la suya (`MacHealth`).
    var capacityRatio: Double? {
        guard let designCapacity, let currentCapacity, designCapacity > 0 else { return nil }
        return Double(currentCapacity) / Double(designCapacity) * 100
    }

    enum Status: Equatable {
        case charging(minutesToFull: Int?)
        /// Enchufado pero sin cargar: el límite de carga de macOS, la carga optimizada,
        /// el calor o que ya está llena. macOS no dice cuál de forma documentada.
        case pluggedNotCharging
        case full
        case onBattery(minutesToEmpty: Int?)
    }

    var status: Status {
        if isPluggedIn {
            if isCharging { return .charging(minutesToFull: minutesToFull) }
            return isFullyCharged ? .full : .pluggedNotCharging
        }
        return .onBattery(minutesToEmpty: minutesToEmpty)
    }

    var statusText: String {
        switch status {
        case .charging(let minutes):
            if let minutes { return L("Cargando · llena en \(Self.duration(minutes))", "Charging · full in \(Self.duration(minutes))") }
            return L("Cargando", "Charging")
        case .pluggedNotCharging:
            return L("Enchufado, sin cargar", "Plugged in, not charging")
        case .full:
            return L("Enchufado · cargada", "Plugged in · charged")
        case .onBattery(let minutes):
            if let minutes { return L("Con batería · quedan \(Self.duration(minutes))", "On battery · \(Self.duration(minutes)) left") }
            return L("Con batería", "On battery")
        }
    }

    /// Lo que dice el notch al enchufar: «Cargando · 30 W · 57 %».
    var chargerPeek: (title: String, subtitle: String) {
        let title = isCharging ? L("Cargando", "Charging") : L("Enchufado", "Plugged in")
        var parts: [String] = []
        if let adapterWatts { parts.append("\(adapterWatts) W") }
        parts.append("\(percent) %")
        if isCharging, let minutesToFull {
            parts.append(L("llena en \(Self.duration(minutesToFull))", "full in \(Self.duration(minutesToFull))"))
        }
        return (title, parts.joined(separator: " · "))
    }

    /// «45 min», «2 h», «2 h 5 min».
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // MARK: - Lectura

    /// La batería ahora mismo, o `nil` en un Mac sin batería.
    static func read() -> BatteryReport? {
        guard var report = fromPowerSources() else { return nil }
        if let registry = registryProperties() {
            report.apply(registry: registry)
        }
        if report.isPluggedIn,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            report.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        return report
    }

    private static func fromPowerSources() -> BatteryReport? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            return BatteryReport(powerSource: info)
        }
        return nil
    }

    /// Lo que da IOKit en `IOPSGetPowerSourceDescription`. Separado para probarlo.
    init(powerSource info: [String: Any]) {
        let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = info[kIOPSMaxCapacityKey] as? Int ?? 100
        percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
        isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
        isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        isFullyCharged = info[kIOPSIsChargedKey] as? Bool ?? false
        // -1 significa «calculando».
        if let minutes = info[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 { minutesToFull = minutes }
        if let minutes = info[kIOPSTimeToEmptyKey] as? Int, minutes > 0 { minutesToEmpty = minutes }
    }

    init() {}

    /// Lo del registro de IOKit (`AppleSmartBattery`). En Apple silicon las cifras en
    /// mAh van dentro de `BatteryData`; en los Intel, sueltas. Se miran los dos sitios.
    mutating func apply(registry: [String: Any]) {
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? {
            (data[key] as? Int) ?? (registry[key] as? Int)
        }
        cycleCount = registry["CycleCount"] as? Int
        designCycleCount = registry["DesignCycleCount9C"] as? Int
        designCapacity = int("DesignCapacity")
        // La «nominal» es la que usa macOS para la salud; la cruda, en los Intel.
        currentCapacity = int("NominalChargeCapacity") ?? (registry["AppleRawMaxCapacity"] as? Int)
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }
}

/// La salud tal como la cuenta macOS («Capacidad máxima» en Ajustes › Batería).
///
/// Sale de `system_profiler`, que tarda unos 50 ms: se pide al abrir la página, nunca
/// de fondo. Se enseña esta y no la cuenta en mAh para no contradecir a Ajustes.
enum MacHealth {
    struct Info: Equatable {
        var maximumCapacity: Int?
        /// «Good», «Service Recommended»… tal cual lo da el sistema.
        var condition: String?
    }

    static func read() async -> Info? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["-json", "SPPowerDataType"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
    }

    /// Separado para probarlo con la salida real de un Mac.
    static func parse(_ json: Data) -> Info? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let health = item["sppower_battery_health_info"] as? [String: Any] else { continue }
            // «100 %» con espacio duro, o «97%»: se quedan las cifras.
            let raw = health["sppower_battery_health_maximum_capacity"] as? String ?? ""
            let digits = raw.filter(\.isNumber)
            return Info(maximumCapacity: Int(digits), condition: health["sppower_battery_health"] as? String)
        }
        return nil
    }

    /// El estado en palabras, sin inventar traducciones para lo que no conocemos.
    static func conditionTitle(_ raw: String) -> String {
        switch raw {
        case "Good": L("Normal", "Normal")
        case "Fair": L("Aceptable", "Fair")
        case "Poor": L("Mala", "Poor")
        case "Service Recommended", "Check Battery": L("Se recomienda revisarla", "Service recommended")
        default: raw
        }
    }
}
