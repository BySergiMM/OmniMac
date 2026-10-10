import Combine
import Foundation
import IOKit.ps

/// Lo que enseña la sección «Batería» de Rendimiento.
///
/// Solo trabaja con la página abierta: lee al aparecer y cuando macOS avisa de un
/// cambio en la alimentación (enchufar, desenchufar, un punto más de carga). Sin
/// temporizador.
@MainActor
final class BatteryPanel: ObservableObject {
    @Published private(set) var report: BatteryReport?
    @Published private(set) var health: MacHealth.Info?
    @Published private(set) var trend: BatteryHistory.Trend?

    private var runLoopSource: CFRunLoopSource?

    func start() {
        refresh()
        BatteryHistory.recordToday()
        trend = BatteryHistory.load().trend
        Task { [weak self] in
            let info = await MacHealth.read()
            self?.health = info
        }
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let panel = Unmanaged<BatteryPanel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { panel.refresh() } }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    private func refresh() {
        let new = BatteryReport.read()
        if new != report { report = new }
    }
}
