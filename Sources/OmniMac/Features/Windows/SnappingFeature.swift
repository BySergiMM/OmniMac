import AppKit
import Carbon.HIToolbox

/// Organiza la ventana activa con atajos de teclado (mitades, cuartos, tercios,
/// maximizar, otra pantalla…) y arrastrándola a los bordes de la pantalla, al
/// estilo de Rectangle/Magnet.
final class SnappingFeature: BaseFeature {
    override var needsAccessibility: Bool { true }

    enum Action: UInt32, CaseIterable {
        case leftHalf = 1
        case rightHalf
        case maximize
        case center
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case topHalf
        case bottomHalf
        case firstThird
        case centerThird
        case lastThird
        case firstTwoThirds
        case lastTwoThirds
        case almostMaximize
        case larger
        case smaller
        case restore
        case nextDisplay
        case previousDisplay

        var keyCode: UInt32 {
            switch self {
            case .leftHalf, .previousDisplay: UInt32(kVK_LeftArrow)
            case .rightHalf, .nextDisplay:    UInt32(kVK_RightArrow)
            case .maximize, .topHalf:         UInt32(kVK_UpArrow)
            case .center, .bottomHalf:        UInt32(kVK_DownArrow)
            case .topLeft:        UInt32(kVK_ANSI_U)
            case .topRight:       UInt32(kVK_ANSI_I)
            case .bottomLeft:     UInt32(kVK_ANSI_J)
            case .bottomRight:    UInt32(kVK_ANSI_K)
            case .firstThird:     UInt32(kVK_ANSI_D)
            case .centerThird:    UInt32(kVK_ANSI_F)
            case .lastThird:      UInt32(kVK_ANSI_G)
            case .firstTwoThirds: UInt32(kVK_ANSI_E)
            case .lastTwoThirds:  UInt32(kVK_ANSI_T)
            case .almostMaximize: UInt32(kVK_Return)
            case .larger:         UInt32(kVK_ANSI_Equal)
            case .smaller:        UInt32(kVK_ANSI_Minus)
            case .restore:        UInt32(kVK_Delete)
            }
        }

        /// ⌃⌥ por defecto; las mitades superior/inferior añaden ⇧ (las flechas solas
        /// ya son maximizar/centrar) y el cambio de pantalla añade ⌘.
        var modifiers: UInt32 {
            switch self {
            case .topHalf, .bottomHalf:          UInt32(controlKey | optionKey | shiftKey)
            case .nextDisplay, .previousDisplay: UInt32(controlKey | optionKey | cmdKey)
            default:                             UInt32(controlKey | optionKey)
            }
        }

        /// Cómo se llama en Ajustes.
        var title: String {
            switch self {
            case .leftHalf:        L("Mitad izquierda", "Left half")
            case .rightHalf:       L("Mitad derecha", "Right half")
            case .topHalf:         L("Mitad superior", "Top half")
            case .bottomHalf:      L("Mitad inferior", "Bottom half")
            case .maximize:        L("Maximizar", "Maximize")
            case .almostMaximize:  L("Casi maximizar (con aire alrededor)", "Almost maximize (with a margin)")
            case .center:          L("Centrar", "Centre")
            case .topLeft:         L("Cuarto de arriba a la izquierda", "Top-left quarter")
            case .topRight:        L("Cuarto de arriba a la derecha", "Top-right quarter")
            case .bottomLeft:      L("Cuarto de abajo a la izquierda", "Bottom-left quarter")
            case .bottomRight:     L("Cuarto de abajo a la derecha", "Bottom-right quarter")
            case .firstThird:      L("Primer tercio", "First third")
            case .centerThird:     L("Tercio central", "Middle third")
            case .lastThird:       L("Último tercio", "Last third")
            case .firstTwoThirds:  L("Dos primeros tercios", "First two thirds")
            case .lastTwoThirds:   L("Dos últimos tercios", "Last two thirds")
            case .larger:          L("Más grande", "Larger")
            case .smaller:         L("Más pequeña", "Smaller")
            case .restore:         L("Restaurar el tamaño anterior", "Restore the previous size")
            case .nextDisplay:     L("Pasar a la pantalla siguiente", "Move to the next display")
            case .previousDisplay: L("Pasar a la pantalla anterior", "Move to the previous display")
            }
        }
    }

    /// Los veintiún atajos del módulo, sacados del propio `Action` para que el valor
    /// de fábrica y el que se registra no puedan separarse nunca.
    ///
    /// Son los que más chocan: quien viene de Rectangle o de Magnet ya tiene ⌃⌥ y las
    /// flechas cogidas, y hasta ahora eso se traducía en que OmniMac no hacía nada
    /// sin decir por qué.
    static let shortcuts: [ShortcutBinding] = Action.allCases.map { action in
        ShortcutBinding(key: "snapping.\(action)",
                        hotKeyID: hotKeyBase + action.rawValue,
                        title: action.title,
                        fallback: Shortcut(keyCode: action.keyCode, modifiers: action.modifiers))
    }

    /// Ajustar arrastrando a los bordes y esquinas (con huella), como Rectangle.
    @Published var snapByDragging: Bool {
        didSet {
            UserDefaults.standard.set(snapByDragging, forKey: "snapping.drag")
            guard isEnabled else { return }
            if snapByDragging { drag.start() } else { drag.stop() }
        }
    }

    /// Repetir un atajo de mitad en la misma ventana cicla ½ → ⅔ → ⅓ (como Rectangle).
    @Published var cycleSizes: Bool {
        didSet { UserDefaults.standard.set(cycleSizes, forKey: "snapping.cycle") }
    }
    private var lastRepeat: (action: Action, window: CGWindowID, at: Date, step: Int)?

    private static let hotKeyBase: UInt32 = 100
    /// Marco de cada ventana antes de su primer ajuste, para «Restaurar».
    private var savedFrames: [CGWindowID: CGRect] = [:]
    private lazy var drag = SnapDragMonitor(
        focusedWindow: { [weak self] in self?.focusedWindow() },
        apply: { [weak self] window, rect in self?.snap(window, to: rect) }
    )

    init() {
        if UserDefaults.standard.object(forKey: "snapping.drag") == nil {
            snapByDragging = true
        } else {
            snapByDragging = UserDefaults.standard.bool(forKey: "snapping.drag")
        }
        cycleSizes = UserDefaults.standard.object(forKey: "snapping.cycle") == nil ? true : UserDefaults.standard.bool(forKey: "snapping.cycle")
        super.init(id: "snapping",
                   name: L("Atajos de ventanas", "Window shortcuts"),
                   symbol: "rectangle.split.2x1",
                   blurb: L("Coloca ventanas en mitades, cuartos, tercios o a pantalla completa con ⌃⌥ + teclas, o arrastrándolas a los bordes.", "Places windows in halves, quarters, thirds or full screen with ⌃⌥ + keys, or by dragging them to the edges."),
                   defaultEnabled: true)
    }

    override func start() {
        WindowLayoutStore.shared.start()
        for (binding, action) in zip(Self.shortcuts, Action.allCases) {
            HotKeyCenter.shared.bind(binding) { [weak self] in self?.perform(action) }
        }
        if snapByDragging { drag.start() }
    }

    override func stop() {
        WindowLayoutStore.shared.stop()
        for binding in Self.shortcuts { HotKeyCenter.shared.unbind(binding) }
        drag.stop()
    }

    private func perform(_ action: Action) {
        guard Permissions.hasAccessibility else {
            Permissions.requestAccessibility()
            return
        }
        guard let window = focusedWindow() else { return }

        let current = currentFrame(of: window)
        guard let screen = screenContaining(current) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        if action == .restore {
            if let id = AX.windowID(window), let saved = savedFrames.removeValue(forKey: id) {
                setFrame(of: window, to: saved)
            }
            return
        }
        remember(window, frame: current)

        // Mitades: repetir el atajo cicla ½ → ⅔ → ⅓ en la misma ventana.
        var fraction: CGFloat = 0.5
        let halves: [Action] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
        if halves.contains(action), cycleSizes, let id = AX.windowID(window) {
            var step = 0
            if let last = lastRepeat, last.action == action, last.window == id,
               Date().timeIntervalSince(last.at) < 3 {
                step = (last.step + 1) % 3
            }
            fraction = [0.5, 2.0 / 3.0, 1.0 / 3.0][step]
            lastRepeat = (action, id, Date(), step)
        } else {
            lastRepeat = nil
        }

        let target: CGRect
        switch action {
        case .leftHalf:       target = Self.rect(visible, x: 0,            y: 0,            w: fraction, h: 1)
        case .rightHalf:      target = Self.rect(visible, x: 1 - fraction, y: 0,            w: fraction, h: 1)
        case .topHalf:        target = Self.rect(visible, x: 0,            y: 1 - fraction, w: 1,        h: fraction)
        case .bottomHalf:     target = Self.rect(visible, x: 0,            y: 0,            w: 1,        h: fraction)
        case .maximize:       target = visible
        case .almostMaximize: target = Self.rect(visible, x: 0.05,  y: 0.05, w: 0.9,  h: 0.9)
        case .center:
            target = CGRect(x: visible.midX - current.width / 2,
                            y: visible.midY - current.height / 2,
                            width: current.width,
                            height: current.height)
        case .topLeft:        target = Self.rect(visible, x: 0,     y: 0.5, w: 0.5,   h: 0.5)
        case .topRight:       target = Self.rect(visible, x: 0.5,   y: 0.5, w: 0.5,   h: 0.5)
        case .bottomLeft:     target = Self.rect(visible, x: 0,     y: 0,   w: 0.5,   h: 0.5)
        case .bottomRight:    target = Self.rect(visible, x: 0.5,   y: 0,   w: 0.5,   h: 0.5)
        case .firstThird:     target = Self.rect(visible, x: 0,     y: 0,   w: 1 / 3, h: 1)
        case .centerThird:    target = Self.rect(visible, x: 1 / 3, y: 0,   w: 1 / 3, h: 1)
        case .lastThird:      target = Self.rect(visible, x: 2 / 3, y: 0,   w: 1 / 3, h: 1)
        case .firstTwoThirds: target = Self.rect(visible, x: 0,     y: 0,   w: 2 / 3, h: 1)
        case .lastTwoThirds:  target = Self.rect(visible, x: 1 / 3, y: 0,   w: 2 / 3, h: 1)
        case .larger:         target = Self.resized(current, by: 40, within: visible)
        case .smaller:        target = Self.resized(current, by: -40, within: visible)
        case .nextDisplay:    target = Self.moved(current, from: screen, to: Self.adjacentScreen(of: screen, step: 1))
        case .previousDisplay: target = Self.moved(current, from: screen, to: Self.adjacentScreen(of: screen, step: -1))
        case .restore:        return
        }
        setFrame(of: window, to: target)
    }

    /// Colocación desde el arrastre a un borde.
    private func snap(_ window: AXUIElement, to rect: CGRect) {
        remember(window, frame: currentFrame(of: window))
        setFrame(of: window, to: rect)
    }

    private func remember(_ window: AXUIElement, frame: CGRect) {
        guard let id = AX.windowID(window) else { return }
        if savedFrames.count > 64 { savedFrames.removeAll() }
        if savedFrames[id] == nil { savedFrames[id] = frame }
    }

    // MARK: - Geometría

    private static func rect(_ v: CGRect, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: v.minX + v.width * x, y: v.minY + v.height * y, width: v.width * w, height: v.height * h).integral
    }

    private static func resized(_ r: CGRect, by delta: CGFloat, within v: CGRect) -> CGRect {
        var out = r.insetBy(dx: -delta / 2, dy: -delta / 2)
        out.size.width = max(200, min(out.width, v.width))
        out.size.height = max(150, min(out.height, v.height))
        out.origin.x = max(v.minX, min(out.minX, v.maxX - out.width))
        out.origin.y = max(v.minY, min(out.minY, v.maxY - out.height))
        return out.integral
    }

    private static func adjacentScreen(of screen: NSScreen, step: Int) -> NSScreen {
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return screen }
        return screens[(index + step + screens.count) % screens.count]
    }

    /// Misma posición y tamaño relativos en la otra pantalla.
    private static func moved(_ r: CGRect, from: NSScreen, to: NSScreen) -> CGRect {
        guard from != to else { return r }
        let a = from.visibleFrame, b = to.visibleFrame
        let fx = (r.minX - a.minX) / max(1, a.width)
        let fy = (r.minY - a.minY) / max(1, a.height)
        let fw = r.width / max(1, a.width)
        let fh = r.height / max(1, a.height)
        return CGRect(x: b.minX + fx * b.width,
                      y: b.minY + fy * b.height,
                      width: min(b.width, fw * b.width),
                      height: min(b.height, fh * b.height)).integral
    }

    // MARK: - Accesibilidad

    private func focusedWindow() -> AXUIElement? {
        // Nunca la nuestra: el notch/Ajustes de OmniMac pueden tener el foco de teclado
        // (por eso NO usamos kAXFocusedApplicationAttribute, que devolvería OmniMac).
        // La app dueña de la barra de menús es siempre la app real del usuario, porque
        // un panel accesorio no la posee.
        let myPID = NSRunningApplication.current.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != myPID else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        return AX.element(axApp, kAXFocusedWindowAttribute as String)
            ?? AX.element(axApp, kAXMainWindowAttribute as String)
            ?? AX.elements(axApp, kAXWindowsAttribute as String).first { AX.string($0, kAXSubroleAttribute as String) == kAXStandardWindowSubrole as String }
    }

    /// Marco actual de la ventana en coordenadas de Cocoa.
    private func currentFrame(of window: AXUIElement) -> CGRect {
        let position = AX.point(window, kAXPositionAttribute as String) ?? .zero
        let size = AX.size(window, kAXSizeAttribute as String) ?? .zero
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: position.x,
                      y: primaryHeight - position.y - size.height,
                      width: size.width,
                      height: size.height)
    }

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            intersectionArea(a.frame, rect) < intersectionArea(b.frame, rect)
        }
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func setFrame(of window: AXUIElement, to cocoaRect: CGRect) {
        AX.setFrame(window, cocoaRect: cocoaRect)
    }
}
