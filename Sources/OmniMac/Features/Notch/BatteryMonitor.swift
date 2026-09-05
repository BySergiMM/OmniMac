import AppKit
import Combine
import IOKit.ps

/// Estado de la batería: nivel, si está cargando y si está enchufada.
struct BatteryState: Equatable {
    var hasBattery = false
    var level = 0          // 0–100
    var isCharging = false
    var isPluggedIn = false
}

/// Estado de la batería en tiempo real (IOKit power sources).
final class BatteryMonitor: ObservableObject {
    @Published private(set) var state = BatteryState()

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private var sampleMode = false

    /// Solo para las capturas de la web.
    func useSample(_ sample: BatteryState) {
        sampleMode = true
        state = sample
    }

    func refresh() {
        guard !sampleMode else { return }
        var newState = BatteryState()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as NSArray? {
            for source in list {
                guard let info = IOPSGetPowerSourceDescription(blob, source as CFTypeRef)?
                    .takeUnretainedValue() as NSDictionary? else { continue }
                guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

                newState.hasBattery = true
                let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maximum = info[kIOPSMaxCapacityKey] as? Int ?? 100
                newState.level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
                newState.isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
                newState.isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            }
        }
        if newState != state {
            state = newState
        }
    }
}
