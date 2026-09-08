import Foundation

/// Avisos cuando algo del Mac se va de madre.
///
/// Lo difícil de un aviso no es detectarlo, es **no ser pesado**. Un umbral pelado
/// da veinte notificaciones seguidas cuando el valor baila alrededor de la línea.
/// Aquí cada regla tiene dos cosas:
///
/// - **Aguante**: hay que pasarse durante varias muestras seguidas, no en un pico.
/// - **Rearme**: una vez avisado, no se vuelve a avisar hasta que la cosa **vuelva a
///   estar bien**. Y con un margen por debajo del umbral, para que rozar la línea no
///   dispare otra vez.
///
/// Todo esto es aritmética pura y está probado: los avisos que molestan son los que
/// nadie prueba.
struct AlertRule: Equatable {
    /// Por encima (o por debajo, si `below`) de esto salta.
    let threshold: Double
    /// Cuántas muestras seguidas hay que aguantar antes de avisar.
    let sustain: Int
    /// Margen para volver a armarse, en las mismas unidades que el umbral.
    let hysteresis: Double
    /// `true` para reglas de «menos de» (disco libre, batería).
    let below: Bool

    init(threshold: Double, sustain: Int = 3, hysteresis: Double? = nil, below: Bool = false) {
        self.threshold = threshold
        self.sustain = sustain
        self.hysteresis = hysteresis ?? threshold * 0.1
        self.below = below
    }
}

/// El estado de una regla entre muestra y muestra.
struct AlertState: Equatable {
    private(set) var streak = 0
    private(set) var fired = false

    /// Mete una muestra y dice si toca avisar **ahora**.
    mutating func update(_ value: Double, rule: AlertRule) -> Bool {
        let bad = rule.below ? value < rule.threshold : value > rule.threshold
        if bad {
            streak += 1
            guard !fired, streak >= rule.sustain else { return false }
            fired = true
            return true
        }
        streak = 0
        // Rearme solo cuando se ha alejado del umbral, no al rozarlo.
        let safe = rule.below ? value > rule.threshold + rule.hysteresis
                              : value < rule.threshold - rule.hysteresis
        if safe { fired = false }
        return false
    }
}

/// Qué se vigila y con qué números.
struct AlertSettings: Equatable {
    var cpuEnabled = true
    var cpuThreshold: Double = 80          // % de todos los núcleos
    var memoryEnabled = true
    var diskEnabled = true
    var diskFreeGB: Double = 10
    var thermalEnabled = true
    var batteryEnabled = true
    var batteryPercent: Double = 15

    static let key = "performance.alerts"
}

/// Un aviso listo para enseñar.
struct PerformanceAlert: Equatable {
    let id: String
    let title: String
    let body: String
    let symbol: String
}

/// Junta las reglas y decide qué avisos salen en cada muestra.
///
/// No sabe nada de notificaciones ni de vistas: se le dan números y devuelve avisos.
/// Así se puede probar entero sin abrir la app.
struct AlertEngine {
    var settings: AlertSettings

    private var cpu = AlertState()
    private var memory = AlertState()
    private var disk = AlertState()
    private var thermal = AlertState()
    private var battery = AlertState()

    init(settings: AlertSettings = AlertSettings()) {
        self.settings = settings
    }

    /// Una muestra del sistema. Los opcionales que no se sepan van a `nil` y esa
    /// regla se salta.
    struct Sample {
        var cpu: Double?
        /// 0 holgada · 1 ajustada · 2 al límite.
        var memoryPressure: Int?
        var diskFreeGB: Double?
        /// 0 fresco · 1 templado · 2 caliente · 3 muy caliente.
        var thermal: Int?
        var batteryPercent: Double?
        /// Con el cargador puesto no se avisa de batería baja.
        var charging = false
    }

    mutating func evaluate(_ sample: Sample) -> [PerformanceAlert] {
        var alerts: [PerformanceAlert] = []

        if settings.cpuEnabled, let value = sample.cpu {
            // Un pico al abrir una app no es noticia; medio minuto al 80 %, sí.
            let rule = AlertRule(threshold: settings.cpuThreshold, sustain: 15, hysteresis: 15)
            if cpu.update(value, rule: rule) {
                alerts.append(.init(id: "cpu",
                                    title: L("La CPU lleva rato al máximo", "The CPU has been maxed out for a while"),
                                    body: L("Por encima del \(Int(settings.cpuThreshold)) % durante medio minuto. Mira en Rendimiento qué app es.",
                                            "Above \(Int(settings.cpuThreshold))% for half a minute. Check Performance to see which app."),
                                    symbol: "cpu"))
            }
        }

        if settings.memoryEnabled, let pressure = sample.memoryPressure {
            let rule = AlertRule(threshold: 1.5, sustain: 5, hysteresis: 0.6)
            if memory.update(Double(pressure), rule: rule) {
                alerts.append(.init(id: "memory",
                                    title: L("Memoria al límite", "Memory pressure is critical"),
                                    body: L("El Mac está comprimiendo memoria para que quepa todo. Cerrar algo lo arreglaría.",
                                            "Your Mac is compressing memory to fit everything. Closing something would help."),
                                    symbol: "memorychip"))
            }
        }

        if settings.diskEnabled, let free = sample.diskFreeGB {
            // Una sola muestra basta: el disco no baila.
            let rule = AlertRule(threshold: settings.diskFreeGB, sustain: 1, hysteresis: 2, below: true)
            if disk.update(free, rule: rule) {
                alerts.append(.init(id: "disk",
                                    title: L("Queda poco disco", "Running low on disk"),
                                    body: L("\(Int(free)) GB libres. El limpiador de apps puede ayudarte a recuperar sitio.",
                                            "\(Int(free)) GB free. The app cleaner can help you get space back."),
                                    symbol: "internaldrive"))
            }
        }

        if settings.thermalEnabled, let state = sample.thermal {
            let rule = AlertRule(threshold: 1.5, sustain: 5, hysteresis: 0.6)
            if thermal.update(Double(state), rule: rule) {
                alerts.append(.init(id: "thermal",
                                    title: L("El Mac se está calentando", "Your Mac is heating up"),
                                    body: L("macOS ha empezado a frenar para bajar la temperatura.",
                                            "macOS has started throttling to cool down."),
                                    symbol: "thermometer.high"))
            }
        }

        if settings.batteryEnabled, let level = sample.batteryPercent, !sample.charging {
            let rule = AlertRule(threshold: settings.batteryPercent, sustain: 1, hysteresis: 5, below: true)
            if battery.update(level, rule: rule) {
                alerts.append(.init(id: "battery",
                                    title: L("Batería baja", "Low battery"),
                                    body: L("Queda un \(Int(level)) %.", "\(Int(level))% left."),
                                    symbol: "battery.25"))
            }
        }

        return alerts
    }
}
