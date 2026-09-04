import AppKit

/// Ajustes sencillos del notch guardados en UserDefaults.
enum NotchSettings {
    static let hoverDelayKey = "notch.hoverDelay"
    /// Segundos con el ratón encima antes de abrir (la animación añade ~0,1 s).
    static var hoverDelay: Double {
        let value = UserDefaults.standard.double(forKey: hoverDelayKey)
        return value > 0 ? value : 0.3
    }
}

/// Vibración del trackpad al abrirse el notch.
///   0 = ninguna
///   1 = mínima: pulso débil del actuador del trackpad (más suave que cualquier
///       patrón público de NSHapticFeedbackManager)
///   2 = suave: patrón público `.alignment`
enum NotchHaptics {
    static let key = "notch.haptic"

    static var level: Int {
        UserDefaults.standard.object(forKey: key) == nil ? 1 : UserDefaults.standard.integer(forKey: key)
    }

    static func play() {
        switch level {
        case 0:
            return
        case 1:
            if !TrackpadActuator.shared.actuate(.weak) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        default:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

/// Acceso directo al actuador háptico del trackpad a través de MultitouchSupport
/// (framework privado, resuelto en tiempo de ejecución con dlopen/dlsym: si algún
/// símbolo falta, `actuate` devuelve false y se usa la API pública).
final class TrackpadActuator {
    static let shared = TrackpadActuator()

    /// IDs de actuación conocidos (los mismos que usa HapticKey).
    enum Strength: Int32 { case weak = 3, medium = 4, strong = 6 }

    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32
    private typealias ListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceIDFn = @convention(c) (CFTypeRef, UnsafeMutablePointer<UInt64>) -> Int32

    private var actuator: CFTypeRef?
    private var actuateFn: ActuateFn?
    private var didSetup = false

    private init() {}

    @discardableResult
    func actuate(_ strength: Strength) -> Bool {
        if !didSetup { setup() }
        guard let actuator, let actuateFn else { return false }
        return actuateFn(actuator, strength.rawValue, 0, 0, 0) == 0
    }

    private func setup() {
        didSetup = true
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSym = dlsym(handle, "MTActuatorOpen"),
              let actuateSym = dlsym(handle, "MTActuatorActuate"),
              let listSym = dlsym(handle, "MTDeviceCreateList"),
              let deviceIDSym = dlsym(handle, "MTDeviceGetDeviceID") else { return }

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let open = unsafeBitCast(openSym, to: OpenFn.self)
        let list = unsafeBitCast(listSym, to: ListFn.self)
        let deviceID = unsafeBitCast(deviceIDSym, to: DeviceIDFn.self)

        guard let devices = list()?.takeRetainedValue() as? [CFTypeRef] else { return }
        for device in devices {
            var id: UInt64 = 0
            guard deviceID(device, &id) == 0, let candidate = create(id)?.takeRetainedValue() else { continue }
            if open(candidate) == 0 {
                actuator = candidate
                actuateFn = unsafeBitCast(actuateSym, to: ActuateFn.self)
                return
            }
        }
    }
}
