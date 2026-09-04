import AppKit
import Carbon.HIToolbox

/// Evita cerrar apps por accidente: ⌘Q solo funciona si lo mantienes pulsado medio
/// segundo. Un toque rápido no hace nada (y te lo dice). No afecta al Finder ni a
/// OmniMac, ni a ⌘⇧Q (cerrar sesión).
final class QuitGuard {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdWork: DispatchWorkItem?
    private var holding = false
    private static let holdSeconds = 0.5
    /// Marca de nuestros eventos sintéticos para que el tap los deje pasar.
    private static let magic: Int64 = 0x4F4D_5149  // "OMQI"

    var isActive: Bool { tap != nil }

    func start() {
        guard tap == nil, Permissions.hasAccessibility else { return }
        let mask: CGEventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let guardian = Unmanaged<QuitGuard>.fromOpaque(refcon).takeUnretainedValue()
            return guardian.handle(type: type, event: event)
        }, userInfo: refcon) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        cancelHold()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Nuestro propio ⌘Q sintético (tras mantener): pasa.
        if event.getIntegerValueField(.eventSourceUserData) == Self.magic {
            return Unmanaged.passUnretained(event)
        }
        // Con el selector ⌘Tab abierto, ⌘Q es "cerrar esa app": no interferimos.
        if FeatureManager.shared.switcher.isSessionActive {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isQ = keyCode == Int(kVK_ANSI_Q)

        switch type {
        case .keyDown:
            guard isQ, flags.contains(.maskCommand),
                  !flags.contains(.maskShift), !flags.contains(.maskControl), !flags.contains(.maskAlternate) else {
                return Unmanaged.passUnretained(event)
            }
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != "com.apple.finder",
                  front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return Unmanaged.passUnretained(event)
            }
            if !holding {
                holding = true
                let name = front.localizedName ?? "la app"
                Toast.show("Mantén pulsado ⌘Q para salir de \(name)", symbol: "hand.raised.fill", duration: Self.holdSeconds + 0.6)
                let work = DispatchWorkItem { [weak self] in self?.quitAfterHold(front) }
                holdWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds, execute: work)
            }
            return nil // ni el toque ni las repeticiones llegan a la app
        case .keyUp:
            if isQ && holding { cancelHold() }
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            if holding && !flags.contains(.maskCommand) { cancelHold() }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func cancelHold() {
        holdWork?.cancel()
        holdWork = nil
        holding = false
    }

    /// Medio segundo mantenido: enviamos un ⌘Q real (marcado) a la app en primer plano.
    private func quitAfterHold(_ app: NSRunningApplication) {
        holding = false
        holdWork = nil
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: false)
        for event in [down, up] {
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: Self.magic)
            event?.post(tap: .cghidEventTap)
        }
    }
}
