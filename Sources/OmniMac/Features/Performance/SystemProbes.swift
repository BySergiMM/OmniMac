import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Las lecturas del sistema, una por una y sin estado.
///
/// Están aparte de `SystemStats` a propósito: aquí vive todo lo que habla con el
/// kernel o con IOKit, y arriba solo queda el histórico y el temporizador. Así la
/// parte con cuentas —convertir contadores en tasas, clasificar la presión de
/// memoria, ordenar procesos— se puede probar sin tocar el hardware.
///
/// **Nada de APIs privadas.** Temperaturas y ventiladores se leen en macOS con
/// `IOHIDEventSystemClient`, que no es pública; por eso no están aquí. Preferimos no
/// tenerlas a que una actualización de macOS rompa la app o Apple la rechace.
enum SystemProbes {

    // MARK: - CPU por núcleo

    /// Contadores acumulados de cada núcleo, en «ticks».
    ///
    /// Son acumulados desde el arranque, así que un valor suelto no dice nada: hay
    /// que restar dos muestras. La misma trampa que ya nos engañó con `IDLEW`.
    static func coreTicks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size))
        }
        let slots = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            let base = core * slots
            return CPUTicks(user: UInt64(info[base + Int(CPU_STATE_USER)]),
                            system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                            idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                            nice: UInt64(info[base + Int(CPU_STATE_NICE)]))
        }
    }

    /// Cuántos núcleos son de eficiencia y cuántos de rendimiento.
    ///
    /// En Apple silicon los primeros de la lista son los de eficiencia. Sirve para
    /// pintarlos de otro color: ver los E-cores trabajando y los P-cores en reposo
    /// explica de un vistazo por qué el Mac va fresco.
    static func coreLayout() -> (efficiency: Int, performance: Int) {
        func sysctl(_ name: String) -> Int? {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return Int(value)
        }
        // En Intel no existen estas claves: todos los núcleos son iguales.
        guard let efficiency = sysctl("hw.perflevel1.logicalcpu"),
              let performance = sysctl("hw.perflevel0.logicalcpu") else {
            return (0, ProcessInfo.processInfo.processorCount)
        }
        return (efficiency, performance)
    }

    // MARK: - Memoria

    static func memory() -> MemorySample? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        return MemorySample(active: Double(stats.active_count) * page,
                            wired: Double(stats.wire_count) * page,
                            compressed: Double(stats.compressor_page_count) * page,
                            free: Double(stats.free_count) * page,
                            total: Double(ProcessInfo.processInfo.physicalMemory))
    }

    /// Espacio de intercambio en uso, en bytes. Lo que de verdad indica que al Mac
    /// se le ha acabado la memoria.
    static func swapUsed() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    // MARK: - GPU

    /// Uso de la GPU en tanto por ciento, o `nil` si el sistema no lo publica.
    ///
    /// Sale del registro de IOKit, que es público: cada acelerador expone un
    /// diccionario `PerformanceStatistics` con «Device Utilization %». En Apple
    /// silicon hay un solo acelerador; en un Mac con GPU externa habría varios y nos
    /// quedamos con el más ocupado.
    static func gpuUsage() -> Double? {
        var best: Double?
        for service in ["IOAccelerator", "AGXAccelerator", "IOGPU"] {
            guard let matching = IOServiceMatching(service) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let dictionary = properties?.takeRetainedValue() as? [String: Any],
                      let performance = dictionary["PerformanceStatistics"] as? [String: Any],
                      let value = performance["Device Utilization %"] as? NSNumber else { continue }
                best = max(best ?? 0, value.doubleValue)
            }
            if best != nil { return best }
        }
        return best
    }

    // MARK: - Disco

    /// Bytes leídos y escritos desde que arrancó el Mac, sumando todos los discos.
    static func diskTotals() -> (read: UInt64, written: UInt64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = dictionary["Statistics"] as? [String: Any] else { continue }
            found = true
            read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return found ? (read, written) : nil
    }

    // MARK: - Batería

    /// Carga y si está enchufado, o `nil` en un Mac sin batería.
    ///
    /// Se lee aquí en vez de tirar del monitor del notch para no obligar a ese
    /// módulo a estar encendido: los avisos tienen que funcionar aunque el notch
    /// esté apagado.
    static func battery() -> (percent: Double, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let state = info[kIOPSPowerSourceStateKey] as? String
            return (Double(current) / Double(max) * 100, state == kIOPSACPowerValue)
        }
        return nil
    }

    // MARK: - Red

    /// Bytes recibidos y enviados desde que arrancó el Mac, por todas las interfaces
    /// menos la de bucle local (que es el Mac hablando consigo mismo).
    static func networkTotals() -> (received: UInt64, sent: UInt64) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                if !name.hasPrefix("lo") {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    received += UInt64(stats.ifi_ibytes)
                    sent += UInt64(stats.ifi_obytes)
                }
            }
            cursor = interface.ifa_next
        }
        return (received, sent)
    }

    /// Espacio libre y total del disco de arranque, en bytes.
    ///
    /// - Parameter fast: con `true` se pide el hueco libre a secas en vez del que
    ///   macOS considera «disponible para lo importante». La diferencia es lo que el
    ///   sistema podría purgar, y calcularlo cuesta **4,96 ms** frente a 0,09: mucho
    ///   para un aviso de «queda poco disco» que salta una vez al minuto, y poco para
    ///   la cifra que se enseña en la página de Rendimiento.
    static func diskSpace(fast: Bool = false) -> (free: Double, total: Double)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let key: URLResourceKey = fast ? .volumeAvailableCapacityKey
                                       : .volumeAvailableCapacityForImportantUsageKey
        guard let values = try? url.resourceValues(forKeys: [key, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity else { return nil }
        let free = fast ? values.volumeAvailableCapacity.map(Double.init)
                        : values.volumeAvailableCapacityForImportantUsage.map(Double.init)
        guard let free else { return nil }
        return (free, Double(total))
    }
}

// MARK: - Tipos con cuentas (probados aparte)

/// Contadores de CPU de un núcleo. Acumulados: solo valen restando dos muestras.
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    /// Porcentaje de ocupación entre esta muestra y una anterior.
    ///
    /// Devuelve `nil` si no hay tiempo transcurrido: sin diferencia no hay tasa que
    /// calcular, y un 0 mentiría igual que un 100.
    func usage(since previous: CPUTicks) -> Double? {
        let busy = Double((user &- previous.user) + (system &- previous.system) + (nice &- previous.nice))
        let idleDelta = Double(idle &- previous.idle)
        let total = busy + idleDelta
        guard total > 0 else { return nil }
        return min(100, max(0, busy / total * 100))
    }
}

/// Reparto de la memoria en un instante, en bytes.
struct MemorySample: Equatable {
    var active: Double
    var wired: Double
    var compressed: Double
    var free: Double
    var total: Double

    /// Lo que Monitor de Actividad llama «memoria usada».
    var used: Double { active + wired + compressed }

    /// La presión de memoria, con los mismos colores que Monitor de Actividad.
    var pressure: MemoryPressure {
        MemoryPressure.level(used: used, compressed: compressed, total: total)
    }
}

/// Cómo de apurado va el Mac de memoria.
enum MemoryPressure: String, Equatable {
    case normal, warning, critical

    var title: String {
        switch self {
        case .normal: L("Holgada", "Normal")
        case .warning: L("Ajustada", "Warning")
        case .critical: L("Al límite", "Critical")
        }
    }

    /// La regla, en corto: lo que manda no es cuánta memoria hay ocupada, sino
    /// cuánta ha tenido que comprimir el sistema para que quepa. Un Mac con el 90 %
    /// ocupado y nada comprimido va perfectamente; uno al 70 % comprimiendo mucho,
    /// no.
    static func level(used: Double, compressed: Double, total: Double) -> MemoryPressure {
        guard total > 0 else { return .normal }
        let occupied = used / total
        let compression = compressed / total
        if compression > 0.25 || occupied > 0.95 { return .critical }
        if compression > 0.10 || occupied > 0.85 { return .warning }
        return .normal
    }
}

/// Convierte dos contadores acumulados en una tasa por segundo.
///
/// Vale para la red y para el disco. Está aquí, suelto y probado, porque es donde
/// se cuelan los errores: contadores que se reinician, muestras separadas por cero
/// segundos, o restas que se dan la vuelta al desbordar.
enum Rate {
    static func perSecond(from previous: UInt64, to current: UInt64, seconds: TimeInterval) -> Double {
        guard seconds > 0 else { return 0 }
        // Si el contador ha bajado es que se reinició (se desmontó un disco, se
        // reinició una interfaz): no hay tasa que dar, mejor cero que un número
        // enorme.
        guard current >= previous else { return 0 }
        return Double(current - previous) / seconds
    }
}
