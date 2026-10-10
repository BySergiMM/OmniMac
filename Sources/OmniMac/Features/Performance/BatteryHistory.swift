import Foundation

/// Cómo va perdiendo capacidad la batería: una lectura al día, guardada en el Mac.
///
/// No hay temporizador propio. Se anota al arrancar la app, en la vuelta de los avisos
/// y al abrir Rendimiento, y solo si ese día aún no había nada: leer el registro de
/// IOKit cuesta lo mismo que nada y así el reposo no cambia.
struct BatteryHistory: Equatable {
    struct Entry: Equatable {
        /// «2026-10-06», en la zona horaria del Mac.
        let day: String
        let capacity: Int
        let cycles: Int?
    }

    private(set) var entries: [Entry] = []

    /// Dos años de días: de sobra para ver la tendencia y poca cosa en disco.
    static let limit = 730

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Anota el día si aún no estaba. Devuelve si ha cambiado algo.
    @discardableResult
    mutating func record(day: String, capacity: Int, cycles: Int?) -> Bool {
        guard capacity > 0, entries.last?.day != day else { return false }
        entries.append(Entry(day: day, capacity: capacity, cycles: cycles))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        return true
    }

    /// Lo que se ha movido desde la primera lectura, o `nil` si aún no hay dos días.
    struct Trend: Equatable {
        let since: String
        let fromCapacity: Int
        let toCapacity: Int
        let fromCycles: Int?
        let toCycles: Int?

        /// En %, negativo si ha bajado.
        var change: Double {
            guard fromCapacity > 0 else { return 0 }
            return Double(toCapacity - fromCapacity) / Double(fromCapacity) * 100
        }

        /// «Desde el 6 oct 2026: 6200 → 6180 mAh (−0,3 %) · 25 → 31 ciclos».
        func summary(languageCode: String = Localization.code) -> String {
            let spanish = languageCode == "es"
            let date = BatteryHistory.displayDate(since, languageCode: languageCode)
            let number = NumberFormatter()
            number.locale = Locale(identifier: languageCode)
            number.maximumFractionDigits = 1
            number.minimumFractionDigits = 1
            number.positivePrefix = "+"
            number.negativePrefix = "−"
            let percent = number.string(from: NSNumber(value: change)) ?? ""
            var text = spanish ? "Desde el \(date): \(fromCapacity) → \(toCapacity) mAh (\(percent) %)"
                               : "Since \(date): \(fromCapacity) → \(toCapacity) mAh (\(percent)%)"
            if let fromCycles, let toCycles {
                text += spanish ? " · \(fromCycles) → \(toCycles) ciclos" : " · \(fromCycles) → \(toCycles) cycles"
            }
            return text
        }
    }

    /// «6 oct 2026» / «Oct 6, 2026».
    static func displayDate(_ day: String, languageCode: String = Localization.code) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter.string(from: date)
    }

    var trend: Trend? {
        guard let first = entries.first, let last = entries.last, first.day != last.day else { return nil }
        return Trend(since: first.day, fromCapacity: first.capacity, toCapacity: last.capacity,
                     fromCycles: first.cycles, toCycles: last.cycles)
    }

    static func dayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Disco

    private static let key = "battery.history"

    static func load(_ defaults: UserDefaults = .standard) -> BatteryHistory {
        let raw = defaults.array(forKey: key) as? [[String: Any]] ?? []
        return BatteryHistory(entries: raw.compactMap { item in
            guard let day = item["day"] as? String, let capacity = item["capacity"] as? Int else { return nil }
            return Entry(day: day, capacity: capacity, cycles: item["cycles"] as? Int)
        })
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(entries.map { entry -> [String: Any] in
            var item: [String: Any] = ["day": entry.day, "capacity": entry.capacity]
            if let cycles = entry.cycles { item["cycles"] = cycles }
            return item
        }, forKey: Self.key)
    }

    /// Último día anotado en esta sesión: el resto de vueltas del día no leen nada.
    private static var recordedDay: String?

    /// Lee la batería y anota hoy si hacía falta. Barato: una consulta a IOKit al día.
    static func recordToday() {
        let today = dayString()
        guard recordedDay != today else { return }
        guard let report = BatteryReport.read(), let capacity = report.currentCapacity else { return }
        recordedDay = today
        var history = load()
        if history.record(day: today, capacity: capacity, cycles: report.cycleCount) {
            history.save()
        }
    }
}
