import AppKit
import CoreAudio

// MARK: - Teclas de volumen y brillo

/// Las teclas de la fila de función que sustituye el HUD propio.
///
/// Llegan como eventos NSSystemDefined (tipo 14, subtipo 8) con el código de tecla en
/// los 16 bits altos de `data1` y el estado en los bajos. Los números son los
/// `NX_KEYTYPE_*` de IOKit (`ev_keymap.h`). La retroiluminación del teclado no está:
/// la sigue pintando macOS.
enum MediaKey: Int {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

struct MediaKeyPress: Equatable {
    let key: MediaKey
    /// Pulsar (también al dejarla apretada, que repite) o soltar.
    let isDown: Bool
    let isRepeat: Bool
    /// ⌥⇧ como en macOS: pasos de un cuarto.
    let fine: Bool

    static let systemDefinedType: UInt32 = 14
    static let auxKeySubtype: Int16 = 8

    /// `nil` si no es una de las teclas que se atienden.
    static func decode(data1: Int, modifiers: NSEvent.ModifierFlags) -> MediaKeyPress? {
        guard let key = MediaKey(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        // 0xA = pulsada, 0xB = soltada; cualquier otra cosa no es de una tecla.
        guard state == 0xA || state == 0xB else { return nil }
        return MediaKeyPress(key: key,
                             isDown: state == 0xA,
                             isRepeat: flags & 0x1 != 0,
                             fine: modifiers.contains(.option) && modifiers.contains(.shift))
    }
}

/// Un paso de volumen o de brillo, en la rejilla de macOS: 16 pasos, o 64 con ⌥⇧.
///
/// Se encaja en la rejilla en vez de sumar un dieciseisavo: si el volumen venía de un
/// deslizador (0,53, por ejemplo), sumando sin más nunca se llegaría a 0 ni a 1 exactos
/// y la barra no casaría con la de macOS.
enum HUDStep {
    static func next(_ current: Float, up: Bool, fine: Bool) -> Float {
        let step: Float = fine ? 1 / 64 : 1 / 16
        let position = current / step
        // El pequeño margen absorbe el error de coma flotante: 0,5 guardado como
        // 0,49999 no debe contar como «por debajo de 8 pasos».
        let target = up ? (position + 0.001).rounded(.down) + 1
                        : (position - 0.001).rounded(.up) - 1
        return min(1, max(0, target * step))
    }
}

/// Lo que enseña el HUD tras atender una tecla.
struct HUDReading: Equatable {
    enum Kind { case volume, brightness }
    let kind: Kind
    let level: Double
    let muted: Bool

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    var title: String {
        switch kind {
        case .volume: muted ? L("Silenciado", "Muted") : L("Volumen", "Volume")
        case .brightness: L("Brillo", "Brightness")
        }
    }
}

// MARK: - Volumen y brillo de verdad

enum SystemLevels {
    /// Atiende la tecla. `nil` si aquí no se puede (un dispositivo de audio sin volumen
    /// propio, como muchas salidas HDMI, o una pantalla sin brillo ajustable): entonces
    /// la tecla sigue su camino y macOS hace lo de siempre, aviso incluido.
    static func apply(_ press: MediaKeyPress) -> HUDReading? {
        switch press.key {
        case .volumeUp, .volumeDown, .mute: return applyVolume(press)
        case .brightnessUp, .brightnessDown: return applyBrightness(press)
        }
    }

    private static func applyVolume(_ press: MediaKeyPress) -> HUDReading? {
        guard let device = AudioSystem.defaultDevice(input: false),
              let current = AudioSystem.volume(of: device, input: false) else { return nil }
        let muted = AudioSystem.isMuted(device, input: false)
        if press.key == .mute {
            // Al dejarla apretada no debe ir encendiendo y apagando.
            guard !press.isRepeat else { return HUDReading(kind: .volume, level: Double(current), muted: muted) }
            AudioSystem.setMuted(!muted, device, input: false)
            let now = AudioSystem.isMuted(device, input: false)
            guard now != muted else { return nil }
            return HUDReading(kind: .volume, level: Double(current), muted: now)
        }
        let up = press.key == .volumeUp
        let target = HUDStep.next(current, up: up, fine: press.fine)
        if target != current {
            AudioSystem.setVolume(target, of: device, input: false)
            // Hay dispositivos que dicen tener volumen pero no lo dejan cambiar: si no
            // se ha movido, que lo resuelva macOS.
            guard let after = AudioSystem.volume(of: device, input: false),
                  abs(after - current) > 0.0001 else { return nil }
        }
        // Como en macOS: subir quita el silencio; bajar hasta cero no lo pone.
        if muted && up { AudioSystem.setMuted(false, device, input: false) }
        let level = AudioSystem.volume(of: device, input: false) ?? target
        return HUDReading(kind: .volume, level: Double(level),
                          muted: AudioSystem.isMuted(device, input: false))
    }

    private static func applyBrightness(_ press: MediaKeyPress) -> HUDReading? {
        guard let services = DisplayServices.shared,
              let display = builtInDisplay(),
              services.canChange(display),
              let current = services.brightness(display) else { return nil }
        let target = HUDStep.next(current, up: press.key == .brightnessUp, fine: press.fine)
        if target != current {
            guard services.setBrightness(display, target) else { return nil }
        }
        return HUDReading(kind: .brightness, level: Double(services.brightness(display) ?? target), muted: false)
    }

    /// La pantalla del portátil, si está encendida (con la tapa cerrada no cuenta).
    /// En un monitor externo las teclas las sigue atendiendo macOS.
    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 }
    }
}

/// El brillo de la pantalla del Mac solo se cambia con DisplayServices, un framework
/// privado (lo mismo que usan MonitorControl y compañía). Se carga a mano: si algún
/// macOS lo quita o cambia, `shared` es nil y las teclas vuelven a macOS sin más.
private final class DisplayServices {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias ChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let get: GetFn
    private let set: SetFn
    private let can: CanFn?
    private let changed: ChangedFn?

    static let shared: DisplayServices? = DisplayServices()

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        self.get = unsafeBitCast(get, to: GetFn.self)
        self.set = unsafeBitCast(set, to: SetFn.self)
        can = dlsym(handle, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanFn.self) }
        changed = dlsym(handle, "DisplayServicesBrightnessChanged").map { unsafeBitCast($0, to: ChangedFn.self) }
    }

    func canChange(_ display: CGDirectDisplayID) -> Bool { can?(display) ?? true }

    func brightness(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        return get(display, &value) == 0 ? value : nil
    }

    func setBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Bool {
        guard set(display, value) == 0 else { return false }
        // Avisa al sistema para que el deslizador de Centro de Control y el brillo
        // automático se enteren del cambio.
        changed?(display, Double(value))
        return true
    }
}

// MARK: - Tap

/// Intercepta las teclas de volumen y brillo antes de que macOS las atienda.
///
/// Tiene que ser a nivel HID: en el de sesión el sistema (SkyLight) ya ha cambiado el
/// volumen y pintado su HUD cuando el evento llega (ver `KeyboardLock`). La máscara
/// solo incluye NSSystemDefined, así que el resto del teclado y el ratón no pasan por
/// aquí ni despiertan la app.
final class MediaKeyTap {
    /// Devuelve true si se ha atendido la tecla (y hay que tragársela).
    var handler: ((MediaKeyPress) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Permissions.hasAccessibility else { return false }
        let mask = CGEventMask(1) << MediaKeyPress.systemDefinedType
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return owner.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: refcon) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS desactiva el tap si tarda; sin reactivarlo, las teclas volverían a
        // macOS a medias y sin avisar.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == MediaKeyPress.systemDefinedType,
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == MediaKeyPress.auxKeySubtype,
              let press = MediaKeyPress.decode(data1: ns.data1, modifiers: ns.modifierFlags),
              handler?(press) == true else { return Unmanaged.passUnretained(event) }
        return nil
    }

    deinit { stop() }
}

