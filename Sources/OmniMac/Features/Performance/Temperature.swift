import Foundation
import IOKit

/// Temperatura del Mac.
///
/// Va en dos niveles a propósito:
///
/// 1. **El estado térmico del sistema** (`ProcessInfo.thermalState`). Es API pública,
///    no se va a romper nunca y dice lo único que de verdad importa: si al Mac le
///    está costando refrigerarse. Esto siempre está.
/// 2. **Los grados**, sensor a sensor. Salen de `IOHIDEventSystemClient`, que **no
///    es API pública**. Los símbolos se piden al cargador en tiempo de ejecución en
///    vez de enlazarlos: si una versión de macOS los quita, aquí no se cae nada —
///    `read()` devuelve `nil` y la app enseña solo el estado térmico.
///
/// Se leen y ya está: no se escribe nada, no se toca el hardware y no hace falta
/// ningún permiso. (Encender y apagar el Bluetooth, por comparar, sí está cerrado en
/// macOS 26: su SPI aborta el proceso que la llama.)
enum Temperature {

    struct Sensor: Identifiable, Equatable {
        let name: String
        let value: Double
        var id: String { name }
    }

    struct Reading: Equatable {
        /// Media de los diodos del chip, en grados.
        let soc: Double?
        /// El diodo más caliente del chip. Es el que decide si el Mac baja el reloj,
        /// así que dice más que la media.
        let socMax: Double?
        /// El SSD, que tiene su propio sensor y se calienta al copiar mucho.
        let ssd: Double?
        /// La batería.
        let battery: Double?
        /// Todos, por si alguien quiere mirarlos uno a uno.
        let sensors: [Sensor]
    }

    /// Lo que dice macOS de cómo va de calor, sin números y sin APIs privadas.
    static var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }

    static func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: L("Fresco", "Nominal")
        case .fair: L("Templado", "Fair")
        case .serious: L("Caliente", "Serious")
        case .critical: L("Muy caliente", "Critical")
        @unknown default: L("Desconocido", "Unknown")
        }
    }

    /// ¿Se pueden leer los grados en este Mac?
    static var available: Bool { Bridge.shared != nil }

    /// Los grados ahora mismo, o `nil` si este macOS ya no deja leerlos.
    static func read() -> Reading? {
        guard let bridge = Bridge.shared else { return nil }
        let raw = bridge.readAll()
        guard !raw.isEmpty else { return nil }
        return reading(from: raw)
    }

    /// Monta la lectura a partir de los pares nombre/valor. Separado de la sonda
    /// para poder probarlo con los nombres reales de un Mac.
    static func reading(from raw: [(name: String, value: Double)]) -> Reading {
        let sensors = deduplicate(raw)
        let die = sensors.filter { isSoC($0.name) }.map(\.value)
        return Reading(soc: average(die),
                       socMax: die.filter { $0 > 1 && $0 < 150 }.max(),
                       ssd: sensors.first { isSSD($0.name) }?.value,
                       battery: sensors.first { isBattery($0.name) }?.value,
                       sensors: sensors)
    }

    /// Quita repetidos y ordena de más caliente a menos.
    ///
    /// La batería aparece seis veces con el mismo nombre (son varias celdas del
    /// medidor). Enseñarla seis veces en la lista sería absurdo: se queda la lectura
    /// más alta de cada nombre.
    static func deduplicate(_ raw: [(name: String, value: Double)]) -> [Sensor] {
        var best: [String: Double] = [:]
        for entry in raw where entry.value > 1 && entry.value < 150 {
            best[entry.name] = max(best[entry.name] ?? 0, entry.value)
        }
        return best.map { Sensor(name: $0.key, value: $0.value) }
            .sorted { $0.value == $1.value ? $0.name < $1.name : $0.value > $1.value }
    }

    /// El sensor del SSD. En Apple silicon se llama «NAND CH0 temp».
    static func isSSD(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("nand") || n.contains("ssd")
    }

    // MARK: - Qué sensor es cada cosa (probado aparte)

    /// Los diodos del chip. En Apple silicon se llaman `tdie` (la pastilla) y
    /// `tdev` (el encapsulado), con el PMU delante.
    ///
    /// **No son núcleos.** Este Mac tiene 10 núcleos y 24 sensores `tdie` repartidos
    /// entre dos PMU, y Apple no publica cuál está al lado de qué. En los Mac Intel
    /// sí había una clave del SMC por núcleo (`TC0C`, `TC1C`…); en Apple silicon
    /// desaparecieron. Por eso aquí hay media y máximo del chip, no «por núcleo»:
    /// inventarse ese reparto sería enseñar un número que no significa nada.
    static func isSoC(_ name: String) -> Bool {
        let n = name.lowercased()
        // `tcal` es el sensor de calibración: lee mucho más alto que el resto y no
        // significa lo que parece. Meterlo en la media daría diez grados de más.
        guard !n.contains("tcal") else { return false }
        return n.contains("tdie") || n.contains("tdev") || n.contains("soc") || n.contains("cpu")
    }

    static func isBattery(_ name: String) -> Bool {
        name.lowercased().contains("battery")
    }

    /// Media, o `nil` si no hay nada que promediar. Se descartan los ceros y los
    /// valores imposibles: un sensor dormido devuelve 0 y hundiría la media.
    static func average(_ values: [Double]) -> Double? {
        let good = values.filter { $0 > 1 && $0 < 150 }
        guard !good.isEmpty else { return nil }
        return good.reduce(0, +) / Double(good.count)
    }

    // MARK: - El puente con la API privada

    /// Carga los símbolos una sola vez y los deja listos.
    ///
    /// Si falta uno, `shared` es `nil` y nadie más se entera: el resto del monitor
    /// sigue funcionando igual.
    private final class Bridge {
        typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias SetMatching  = @convention(c) (AnyObject, CFDictionary) -> Void
        typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
        typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
        typealias CopyEvent    = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
        typealias EventFloat   = @convention(c) (AnyObject, Int32) -> Double

        /// El tipo de evento «temperatura» y el campo donde viene el valor.
        private static let temperatureEvent: Int64 = 15
        private static let temperatureField: Int32 = 15 << 16
        /// Página y uso de los sensores de temperatura de Apple.
        private static let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]

        static let shared: Bridge? = Bridge()

        private let client: AnyObject
        private let copyServices: CopyServices
        private let copyProperty: CopyProperty
        private let copyEvent: CopyEvent
        private let eventFloat: EventFloat

        init?() {
            guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
                  let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
                  let matchSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
                  let servicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
                  let propertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
                  let eventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
                  let floatSym = dlsym(handle, "IOHIDEventGetFloatValue") else { return nil }

            let create = unsafeBitCast(createSym, to: CreateClient.self)
            guard let created = create(kCFAllocatorDefault) else { return nil }
            client = created.takeRetainedValue()

            unsafeBitCast(matchSym, to: SetMatching.self)(client, Self.matching as CFDictionary)
            copyServices = unsafeBitCast(servicesSym, to: CopyServices.self)
            copyProperty = unsafeBitCast(propertySym, to: CopyProperty.self)
            copyEvent = unsafeBitCast(eventSym, to: CopyEvent.self)
            eventFloat = unsafeBitCast(floatSym, to: EventFloat.self)
        }

        func readAll() -> [(name: String, value: Double)] {
            guard let servicesRef = copyServices(client),
                  let services = servicesRef.takeRetainedValue() as? [AnyObject] else { return [] }
            var result: [(String, Double)] = []
            result.reserveCapacity(services.count)
            for service in services {
                guard let event = copyEvent(service, Self.temperatureEvent, 0, 0) else { continue }
                let value = eventFloat(event.takeRetainedValue(), Self.temperatureField)
                guard value > 0 else { continue }
                let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
                result.append((name, value))
            }
            return result
        }
    }
}
