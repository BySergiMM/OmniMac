import AppKit
import Carbon.HIToolbox

/// Sustituye el ⌘Tab del sistema por un selector de VENTANAS (no de apps),
/// al estilo de Windows o AltTab. Con el selector abierto: escribe para buscar,
/// ⌘W cierra la ventana elegida, ⌘M la minimiza, ⌘H oculta su app y ⌘Q la cierra.
final class WindowSwitcherFeature: BaseFeature {
    override var needsAccessibility: Bool { true }

    /// Incluir también las ventanas minimizadas en el selector.
    @Published var includeMinimized: Bool {
        didSet { UserDefaults.standard.set(includeMinimized, forKey: "switcher.includeMinimized") }
    }

    /// Miniaturas en vivo de cada ventana (como AltTab). Necesita Grabación de pantalla.
    @Published var showThumbnails: Bool {
        didSet { UserDefaults.standard.set(showThumbnails, forKey: "switcher.showThumbnails") }
    }

    /// Abrir el selector también con ⌥Tab (el ⌘Tab sigue funcionando).
    @Published var useOptionTab: Bool {
        didSet { UserDefaults.standard.set(useOptionTab, forKey: "switcher.optionTab") }
    }

    /// Modificador con el que se abrió la sesión: al soltarlo se confirma.
    private var sessionModifier: CGEventFlags = .maskCommand

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private let panel = SwitcherPanelController()
    private var sessionActive = false
    /// Selector abierto (⌘ o ⌥ mantenidos).
    var isSessionActive: Bool { sessionActive }

    init() {
        if UserDefaults.standard.object(forKey: "switcher.includeMinimized") == nil {
            includeMinimized = true
        } else {
            includeMinimized = UserDefaults.standard.bool(forKey: "switcher.includeMinimized")
        }
        if UserDefaults.standard.object(forKey: "switcher.showThumbnails") == nil {
            showThumbnails = true
        } else {
            showThumbnails = UserDefaults.standard.bool(forKey: "switcher.showThumbnails")
        }
        useOptionTab = UserDefaults.standard.bool(forKey: "switcher.optionTab")
        super.init(id: "switcher",
                   name: "⌘Tab por ventanas",
                   symbol: "rectangle.on.rectangle",
                   blurb: "Al pulsar ⌘Tab verás todas las ventanas, no solo las apps. Escribe para buscar.",
                   defaultEnabled: true)

        panel.onCommit = { [weak self] in self?.endSession(commit: true) }
    }

    override func start() {
        installTapIfPossible()
        scheduleRetryIfNeeded()
    }

    override func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        endSession(commit: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    /// Reintenta instalar el tap (por ejemplo, justo después de conceder Accesibilidad).
    func retryStartIfNeeded() {
        guard isEnabled, eventTap == nil else { return }
        installTapIfPossible()
        scheduleRetryIfNeeded()
    }

    /// El permiso puede llegar (o perderse tras recompilar) en cualquier momento:
    /// reintentamos en segundo plano hasta que el tap quede instalado.
    private func scheduleRetryIfNeeded() {
        guard eventTap == nil, retryTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.installTapIfPossible()
            if self.eventTap != nil {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
        timer.tolerance = 1.0
        retryTimer = timer
    }

    private func installTapIfPossible() {
        guard eventTap == nil else { return }
        guard Permissions.hasAccessibility else { return } // el aviso aparece en Ajustes y en el menú

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)) |
            (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue))

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let feature = Unmanaged<WindowSwitcherFeature>.fromOpaque(refcon).takeUnretainedValue()
                return feature.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Gestión de eventos

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            return handleKeyDown(event)

        case .flagsChanged:
            // Al soltar ⌘ confirmamos la selección, como el selector nativo.
            if sessionActive && !event.flags.contains(sessionModifier) {
                endSession(commit: true)
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if !sessionActive {
            let isTab = keyCode == Int(kVK_Tab) && !flags.contains(.maskControl)
            let isCmdTab = isTab && flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
            let isOptTab = useOptionTab && isTab && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
            guard isCmdTab || isOptTab else { return Unmanaged.passUnretained(event) }
            sessionModifier = isCmdTab ? .maskCommand : .maskAlternate

            if beginSession(backward: flags.contains(.maskShift)) {
                return nil // consumimos el evento: el selector nativo no aparece
            }
            return Unmanaged.passUnretained(event) // sin ventanas → dejamos el nativo
        }

        // Mientras el selector está abierto (⌘ pulsado), el teclado es nuestro.
        switch keyCode {
        case Int(kVK_Tab):        panel.advance(flags.contains(.maskShift) ? -1 : 1)
        case Int(kVK_LeftArrow):  panel.advance(-1)
        case Int(kVK_RightArrow): panel.advance(1)
        case Int(kVK_UpArrow):    panel.advanceRow(-1)
        case Int(kVK_DownArrow):  panel.advanceRow(1)
        case Int(kVK_Escape):     endSession(commit: false)
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter): endSession(commit: true)
        case Int(kVK_Delete):     panel.filterBackspace()
        case Int(kVK_ANSI_W):     panel.closeSelected(); endSessionIfEmpty()
        case Int(kVK_ANSI_M):     panel.minimizeSelected(); endSessionIfEmpty()
        case Int(kVK_ANSI_H):     panel.hideSelectedApp(); endSessionIfEmpty()
        case Int(kVK_ANSI_Q):     panel.quitSelectedApp(); endSessionIfEmpty()
        default:
            if let typed = Self.typedCharacters(event) {
                panel.filterAppend(typed)
            }
        }
        return nil
    }

    /// Letras, números y espacio que se escriben con el selector abierto (para buscar).
    private static func typedCharacters(_ event: CGEvent) -> String? {
        // Sin modificadores: con ⌥ pulsado, la tecla "a" daría "å".
        guard let plain = event.copy() else { return nil }
        plain.flags = []
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        plain.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " "))
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return text
    }

    private func beginSession(backward: Bool) -> Bool {
        let windows = WindowEnumerator.windows(includeMinimized: includeMinimized)
        guard !windows.isEmpty else { return false }
        sessionActive = true
        let initial = windows.count > 1 ? (backward ? windows.count - 1 : 1) : 0
        panel.show(windows: windows,
                   initialSelection: initial,
                   thumbnails: showThumbnails && Permissions.hasScreenRecording)
        return true
    }

    private func endSessionIfEmpty() {
        if panel.isEmpty { endSession(commit: false) }
    }

    private func endSession(commit: Bool) {
        guard sessionActive else { return }
        sessionActive = false
        let selected = panel.selectedWindow
        panel.hide()
        if commit, let selected {
            WindowEnumerator.focus(selected)
        }
    }
}
