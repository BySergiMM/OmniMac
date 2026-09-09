import Combine
import Foundation

/// Vigila el Mac de fondo y avisa cuando algo se va de madre.
///
/// Es el único trozo del módulo de rendimiento que corre **sin que nadie esté
/// mirando**, así que se ha hecho lo más barato posible:
///
/// - Una muestra cada **minuto**, con tolerancia, para que macOS agrupe los
///   despertares.
/// - Solo lo que cuesta cuatro llamadas al sistema: CPU, presión de memoria, disco
///   libre, estado térmico y batería. **Nada de GPU, sensores de temperatura ni
///   recorrer los 445 procesos**: eso solo se hace con la página abierta.
/// - Si están todas las reglas apagadas, ni temporizador hay.
@MainActor
final class AlertsMonitor: ObservableObject {
    static let shared = AlertsMonitor()

    @Published var settings: AlertSettings {
        didSet {
            save()
            engine.settings = settings
            reschedule()
        }
    }

    /// Cada cuánto se mira.
    ///
    /// Un minuto. A treinta segundos el reposo subía de 0,017 % a 0,067 %, y para
    /// algo que avisa por notificación no cambia nada esperar el doble.
    private static let interval: TimeInterval = 60

    private var engine: AlertEngine
    private var timer: Timer?
    private var lastTicks: [CPUTicks] = []
    private var running = false
    /// El disco se mira una de cada diez vueltas: diez minutos.
    ///
    /// Aun con la lectura rápida, mirar el disco es lo más caro de la vuelta y no se
    /// llena en un minuto.
    private static let diskEvery = 10
    private var ticks = 0

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: AlertSettings.key) as? [String: Any] ?? [:]
        var loaded = AlertSettings()
        func flag(_ key: String, _ fallback: Bool) -> Bool { stored[key] as? Bool ?? fallback }
        loaded.cpuEnabled = flag("cpu", true)
        loaded.memoryEnabled = flag("memory", true)
        loaded.diskEnabled = flag("disk", true)
        loaded.thermalEnabled = flag("thermal", true)
        loaded.batteryEnabled = flag("battery", true)
        loaded.cpuThreshold = stored["cpuThreshold"] as? Double ?? 80
        loaded.diskFreeGB = stored["diskFreeGB"] as? Double ?? 10
        loaded.batteryPercent = stored["batteryPercent"] as? Double ?? 15
        settings = loaded
        engine = AlertEngine(settings: loaded)
    }

    private func save() {
        UserDefaults.standard.set([
            "cpu": settings.cpuEnabled, "memory": settings.memoryEnabled,
            "disk": settings.diskEnabled, "thermal": settings.thermalEnabled,
            "battery": settings.batteryEnabled,
            "cpuThreshold": settings.cpuThreshold, "diskFreeGB": settings.diskFreeGB,
            "batteryPercent": settings.batteryPercent,
        ], forKey: AlertSettings.key)
    }

    /// ¿Hay algo que vigilar?
    private var anythingEnabled: Bool {
        settings.cpuEnabled || settings.memoryEnabled || settings.diskEnabled
            || settings.thermalEnabled || settings.batteryEnabled
    }

    func start() {
        running = true
        reschedule()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard running, anythingEnabled else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            // El temporizador ya dispara en el hilo principal: saltar a una tarea
            // solo para volver al mismo sitio creaba un hilo de concurrencia entero.
            MainActor.assumeIsolated { self?.check() }
        }
        // Un cuarto de la ventana: macOS agrupa este despertar con los suyos.
        t.tolerance = Self.interval / 4
        timer = t
    }

    private func check() {
        ticks += 1
        var sample = AlertEngine.Sample()

        if settings.cpuEnabled {
            let now = SystemProbes.coreTicks()
            defer { lastTicks = now }
            if lastTicks.count == now.count, !now.isEmpty {
                let perCore = zip(now, lastTicks).compactMap { $0.usage(since: $1) }
                if !perCore.isEmpty { sample.cpu = perCore.reduce(0, +) / Double(perCore.count) }
            }
        }
        if settings.memoryEnabled, let memory = SystemProbes.memory() {
            sample.memoryPressure = switch memory.pressure {
            case .normal: 0
            case .warning: 1
            case .critical: 2
            }
        }
        if settings.diskEnabled, ticks % Self.diskEvery == 1, let space = SystemProbes.diskSpace(fast: true) {
            sample.diskFreeGB = space.free / 1_073_741_824
        }
        if settings.thermalEnabled {
            sample.thermal = switch Temperature.thermalState {
            case .nominal: 0
            case .fair: 1
            case .serious: 2
            case .critical: 3
            @unknown default: 0
            }
        }
        if settings.batteryEnabled, let battery = SystemProbes.battery() {
            sample.batteryPercent = battery.percent
            sample.charging = battery.charging
        }

        for alert in engine.evaluate(sample) {
            Notifier.post(title: alert.title, body: alert.body, identifier: "alert.\(alert.id)")
        }
    }
}
