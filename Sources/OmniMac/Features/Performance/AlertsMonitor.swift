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
///   libre, estado térmico y batería. **Nada de GPU ni recorrer los 445
///   procesos**: eso solo se hace con la página abierta. Los sensores de
///   temperatura, solo para el aviso de batería caliente: con el cargador puesto y
///   una vuelta de cada dos.
/// - Si están todas las reglas apagadas, ni temporizador hay.
@MainActor
final class AlertsMonitor: ObservableObject {
    static let shared = AlertsMonitor()

    @Published var settings: AlertSettings {
        didSet {
            save()
            engine.settings = settings
            reschedule()
            // Encender un aviso es el momento de pedir permiso, no cuando ya ha saltado.
            if anythingEnabled { askForPermission() }
        }
    }

    /// Si macOS deja que los avisos se vean. Lo enseña la página de Rendimiento.
    @Published private(set) var permission: Notifier.Permission = .allowed

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
        loaded.unplugEnabled = flag("unplug", false)
        loaded.unplugPercent = stored["unplugPercent"] as? Double ?? 80
        loaded.batteryHeatEnabled = flag("batteryHeat", true)
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
            "unplug": settings.unplugEnabled, "unplugPercent": settings.unplugPercent,
            "batteryHeat": settings.batteryHeatEnabled,
        ], forKey: AlertSettings.key)
    }

    /// ¿Hay algo que vigilar?
    private var anythingEnabled: Bool {
        settings.cpuEnabled || settings.memoryEnabled || settings.diskEnabled
            || settings.thermalEnabled || anyBatteryRule
    }

    private var anyBatteryRule: Bool {
        settings.batteryEnabled || settings.unplugEnabled || settings.batteryHeatEnabled
    }

    func start() {
        running = true
        reschedule()
        if anythingEnabled { askForPermission() }
    }

    /// Enseña el cuadro de macOS si aún no se ha preguntado; si ya se decidió, solo lo lee.
    func askForPermission() {
        Task { permission = await Notifier.requestIfNeeded() }
    }

    /// Vuelve a mirar el permiso (al abrir la página o al volver de Ajustes del Sistema).
    func refreshPermission() {
        Task { permission = await Notifier.permission() }
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
        if anyBatteryRule, let battery = SystemProbes.battery() {
            sample.batteryPercent = battery.percent
            sample.charging = battery.charging
            // Los sensores de temperatura son lo caro de la vuelta: solo con el
            // cargador puesto (que es cuando la batería se calienta) y cada dos minutos.
            if settings.batteryHeatEnabled, battery.charging, ticks % 2 == 0 {
                sample.batteryTemperature = Temperature.read()?.battery
            }
            // Una vez al día se anota la capacidad; el resto de días no hace nada.
            BatteryHistory.recordToday()
        }

        for alert in engine.evaluate(sample) {
            Notifier.post(title: alert.title, body: alert.body, identifier: "alert.\(alert.id)")
        }
    }
}
