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

    /// Registra un atajo. Devuelve **si lo consiguió**: `RegisterEventHotKey` falla
    /// cuando otra app ya tiene esa combinación, y quien llama tiene que poder
    /// contarlo. Antes el resultado se tiraba y la función se quedaba muda.
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  handler: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        handlers[id] = handler
        releaseHandlers[id] = onRelease

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4D_4E49) /* "OMNI" */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    /// Enlaza una acción a su atajo configurable.
    ///
    /// Lee de `ShortcutStore` lo que toque (el del usuario o el de fábrica), lo
    /// registra y **apunta si se quedó sin sitio**, para que Ajustes lo enseñe. Se
    /// queda además con cómo volver a registrarlo, porque cuando el usuario cambia
    /// el atajo hay que rehacerlo sin que el módulo tenga que enterarse.
    func bind(_ binding: ShortcutBinding,
              handler: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        let store = ShortcutStore.shared
        store.remember(binding) { [weak self] in
            self?.bind(binding, handler: handler, onRelease: onRelease)
        }
        guard let shortcut = store.shortcut(for: binding) else {
            // Sin atajo a propósito: ni se registra ni se avisa de nada.
            unregister(id: binding.hotKeyID)
            store.markUnavailable(binding, false)
            return
        }
        let ok = register(id: binding.hotKeyID, keyCode: shortcut.keyCode,
                          modifiers: shortcut.modifiers, handler: handler, onRelease: onRelease)
        store.markUnavailable(binding, !ok)
    }

    /// Suelta el atajo de una acción configurable.
    func unbind(_ binding: ShortcutBinding) {
        unregister(id: binding.hotKeyID)
        ShortcutStore.shared.forget(binding)
        ShortcutStore.shared.markUnavailable(binding, false)
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
