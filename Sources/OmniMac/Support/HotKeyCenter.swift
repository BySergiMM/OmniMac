import Carbon.HIToolbox

/// Registro central de atajos globales (Carbon), compartido por los módulos.
/// No requiere permisos especiales.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    fileprivate var handlers: [UInt32: () -> Void] = [:]
    /// Opcional: qué hacer al soltar la tecla (para distinguir toque de mantener).
    fileprivate var releaseHandlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    private init() {}

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  handler: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        installHandlerIfNeeded()
        unregister(id: id)
        handlers[id] = handler
        releaseHandlers[id] = onRelease

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4D_4E49) /* "OMNI" */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
        releaseHandlers[id] = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                HotKeyCenter.shared.releaseHandlers[hotKeyID.id]?()
            } else {
                HotKeyCenter.shared.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 2, &eventTypes, nil, nil)
    }
}
