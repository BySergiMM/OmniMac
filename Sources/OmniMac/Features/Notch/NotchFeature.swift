import AppKit
import Combine
import SwiftUI

/// Convierte el notch en un pequeño centro de control (estilo BoringNotch):
/// pestaña de música, pestaña de bandeja con AirDrop, batería y accesos rápidos.
final class NotchFeature: BaseFeature {
    /// Mostrar la "isla" también en pantallas sin notch físico.
    @Published var showWithoutNotch: Bool {
        didSet {
            UserDefaults.standard.set(showWithoutNotch, forKey: "notch.showWithoutNotch")
            if isEnabled { rebuild() }
        }
    }

    /// Ocultar el notch cuando la app en primer plano está a pantalla completa
    /// (vídeo, juegos, presentaciones…).
    @Published var hideInFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(hideInFullscreen, forKey: "notch.hideFullscreen")
            controller?.hideInFullscreen = hideInFullscreen
        }
    }

    /// Vistazo rápido: título y artista bajo el notch unos segundos al cambiar de canción.
    /// Tarjeta al estilo iPhone al conectar AirPods o Beats.
    @Published var headphonesCard: Bool {
        didSet {
            UserDefaults.standard.set(headphonesCard, forKey: "notch.headphonesCard")
            updateHeadphonesWatcher()
        }
    }
    /// Intentar cerrar el aviso de Control Center (experimental).
    @Published var hideSystemBanner: Bool {
        didSet {
            UserDefaults.standard.set(hideSystemBanner, forKey: "notch.hideSystemBanner")
            controller?.hideSystemBanner = hideSystemBanner
        }
    }
    private let headphones = HeadphonesWatcher()

    @Published var sneakPeek: Bool {
        didSet {
            UserDefaults.standard.set(sneakPeek, forKey: "notch.sneakPeek")
            controller?.sneakPeekEnabled = sneakPeek
        }
    }

    /// Pestañas del notch activas (se eligen en Ajustes). Se guarda lo DESACTIVADO:
    /// así una pestaña nueva de una versión posterior nace activada.
    @Published var enabledTabs: Set<NotchTab> {
        didSet {
            let disabled = Set(NotchTab.allCases).subtracting(enabledTabs)
            UserDefaults.standard.set(disabled.map(\.rawValue), forKey: "notch.disabledTabs")
            controller?.enabledTabs = enabledTabs
        }
    }

    /// Botones de la cabecera (a la derecha): café, Ajustes y batería.
    @Published var showCoffeeButton: Bool {
        didSet { UserDefaults.standard.set(showCoffeeButton, forKey: "notch.showCoffee"); controller?.showCoffee = showCoffeeButton }
    }
    @Published var showSettingsButton: Bool {
        didSet { UserDefaults.standard.set(showSettingsButton, forKey: "notch.showSettings"); controller?.showSettings = showSettingsButton }
    }
    @Published var showBattery: Bool {
        didSet { UserDefaults.standard.set(showBattery, forKey: "notch.showBattery"); controller?.showBattery = showBattery }
    }

    private var controller: NotchWindowController?
    private let keepAwake: KeepAwakeFeature
    private let sound: SoundFeature
    private var screenObserver: Any?

    init(keepAwake: KeepAwakeFeature, sound: SoundFeature) {
        self.keepAwake = keepAwake
        self.sound = sound
        let defaults = UserDefaults.standard
        showWithoutNotch = defaults.object(forKey: "notch.showWithoutNotch") == nil ? true : defaults.bool(forKey: "notch.showWithoutNotch")
        hideInFullscreen = defaults.object(forKey: "notch.hideFullscreen") == nil ? true : defaults.bool(forKey: "notch.hideFullscreen")
        sneakPeek = defaults.object(forKey: "notch.sneakPeek") == nil ? true : defaults.bool(forKey: "notch.sneakPeek")
        headphonesCard = defaults.object(forKey: "notch.headphonesCard") == nil ? true : defaults.bool(forKey: "notch.headphonesCard")
        hideSystemBanner = defaults.object(forKey: "notch.hideSystemBanner") == nil ? true : defaults.bool(forKey: "notch.hideSystemBanner")
        showCoffeeButton = defaults.object(forKey: "notch.showCoffee") == nil ? true : defaults.bool(forKey: "notch.showCoffee")
        showSettingsButton = defaults.object(forKey: "notch.showSettings") == nil ? true : defaults.bool(forKey: "notch.showSettings")
        showBattery = defaults.object(forKey: "notch.showBattery") == nil ? true : defaults.bool(forKey: "notch.showBattery")
        if let disabled = defaults.array(forKey: "notch.disabledTabs") as? [String] {
            enabledTabs = Set(NotchTab.allCases).subtracting(disabled.compactMap(NotchTab.init(rawValue:)))
        } else if let legacy = defaults.array(forKey: "notch.tabs") as? [String] {
            // Formato antiguo (lista de activas): lo que no estaba en la lista y ya
            // existía entonces queda desactivado; las pestañas nuevas, activadas.
            let known: Set<NotchTab> = [.media, .tray, .calendar, .sound, .performance]
            let active = Set(legacy.compactMap(NotchTab.init(rawValue:)))
            enabledTabs = Set(NotchTab.allCases).subtracting(known.subtracting(active))
            defaults.removeObject(forKey: "notch.tabs")
        } else {
            enabledTabs = Set(NotchTab.allCases)
        }
        super.init(id: "notch",
                   name: L("Notch dinámico", "Dynamic notch"),
                   symbol: "sparkles.rectangle.stack",
                   blurb: L("Música, AirDrop, batería y accesos rápidos al pasar el ratón por el notch.", "Music, AirDrop, battery and quick actions when you hover the notch."),
                   defaultEnabled: true)
    }

    private func updateHeadphonesWatcher() {
        guard isEnabled, headphonesCard else { headphones.stop(); return }
        headphones.onConnect = { [weak self] info in self?.controller?.presentHeadphones(info) }
        headphones.onUpdate = { [weak self] info in self?.controller?.updateHeadphones(info) }
        headphones.start()
    }

    /// Botón «Probar» de Ajustes: enseña la tarjeta con datos de ejemplo.
    func previewHeadphones() {
        var first = HeadphonesInfo.sample
        first.left = nil; first.right = nil; first.caseLevel = nil
        controller?.presentHeadphones(first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.controller?.updateHeadphones(HeadphonesInfo.sample)
        }
    }

    override func start() {
        updateHeadphonesWatcher()
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    override func stop() {
        headphones.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        controller?.close()
        controller = nil
    }

    private func rebuild() {
        controller?.close()
        controller = nil

        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        // Sin notch físico usamos la pantalla principal (la de la barra de menús),
        // no la que tenga el foco en ese momento.
        let screen = notchScreen ?? (showWithoutNotch ? NSScreen.screens.first : nil)
        guard let screen else { return }
        let controller = NotchWindowController(screen: screen, keepAwake: keepAwake, sound: sound)
        controller.hideInFullscreen = hideInFullscreen
        controller.sneakPeekEnabled = sneakPeek
        controller.enabledTabs = enabledTabs
        controller.hideSystemBanner = hideSystemBanner
        controller.showCoffee = showCoffeeButton
        controller.showSettings = showSettingsButton
        controller.showBattery = showBattery
        self.controller = controller
    }
}

// MARK: - Modelo

enum NotchTab: String, CaseIterable {
    case media
    case tray
    case calendar
    case sound
    case timer
    case performance

    var title: String {
        switch self {
        case .media: L("Música", "Music")
        case .tray: L("Bandeja y AirDrop", "Tray and AirDrop")
        case .calendar: L("Calendario", "Calendar")
        case .sound: L("Sonido y volumen por app", "Sound and per-app volume")
        case .timer: L("Temporizador", "Timer")
        case .performance: L("Rendimiento", "Performance")
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .tray: "tray.full.fill"
        case .calendar: "calendar"
        case .sound: "speaker.wave.2.fill"
        case .timer: "timer"
        case .performance: "gauge.with.dots.needle.33percent"
        }
    }

    var settingsHint: String {
        switch self {
        case .media: L("Carátula, progreso y controles de Spotify o Música.", "Artwork, progress and controls for Spotify or Music.")
        case .tray: L("Archivos a mano y zona AirDrop.", "Files at hand and an AirDrop zone.")
        case .calendar: L("Los eventos de hoy (pide permiso de Calendario).", "Today's events (asks for Calendar permission).")
        case .sound: L("Salida de audio y volumen distinto para cada app.", "Audio output and a different volume for every app.")
        case .timer: L("Cuenta atrás y Pomodoro; el tiempo restante se ve junto al icono de la barra de menús.", "Countdown and Pomodoro; the time left shows next to the menu-bar icon.")
        case .performance: L("CPU, memoria y red del último minuto.", "CPU, memory and network for the last minute.")
        }
    }

    /// Las de la izquierda de la barra; Rendimiento va a la derecha porque el quinto
    /// botón a la izquierda quedaba bajo el notch físico.
    static let leftTabs: [NotchTab] = [.media, .tray, .calendar, .sound, .timer]
}

/// Dónde caería un archivo arrastrado: bandeja o AirDrop.
enum NotchDropZone {
    case none
    case shelf
    case airdrop
}

/// Lo que enseña el vistazo rápido bajo el notch: una canción nueva o un aviso.
struct PeekInfo: Equatable {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: NSColor?
}

/// Posición del ratón dentro del panel (coordenadas del hosting view, origen
/// arriba-izquierda) mientras está expandido. La alimenta el controlador desde los
/// monitores de movimiento — el `.onHover` de SwiftUI no funciona en este panel sin
/// activación — y solo la observan las vistas con efecto hover (los botones).
final class HoverState: ObservableObject {
    @Published var point: CGPoint?
}

final class NotchModel: ObservableObject {
    let hover = HoverState()
    @Published var expanded = false
    /// El contenido (carátula, controles…) se muestra un poco DESPUÉS de que el
    /// negro haya crecido y se oculta al instante al plegar: así nada asoma fuera.
    @Published var showContent = false
    @Published var tab: NotchTab = .media
    @Published var shelf: [URL] = []
    /// Vistazo rápido (solo plegado): el negro crece un poco hacia abajo con el texto.
    @Published var peek: PeekInfo?
    /// Con notch físico, plegado NO se dibuja nada (el notch ya es negro): así nunca
    /// aparece un rectángulo negro al cambiar de escritorio ni en Mission Control.
    /// Se pone a true (sin animación) justo antes de abrir o de enseñar el vistazo.
    @Published var blackVisible = false
    /// Pestañas activas (Ajustes › Notch).
    @Published var enabledTabs: Set<NotchTab> = Set(NotchTab.allCases)
    /// Botones de la cabecera.
    @Published var showCoffee = true
    @Published var showSettings = true
    @Published var showBattery = true
    /// Zona que se resaltará mientras se arrastra un archivo por encima.
    @Published var dropZone: NotchDropZone = .none
    /// Tarjeta «AirPods conectados» (sustituye a las pestañas mientras se enseña).
    @Published var deviceCard: HeadphonesInfo?

    let hasNotch: Bool
    let notchSize: CGSize
    let expandedSize: CGSize

    static let peekExtraHeight: CGFloat = 30
    /// Espacio mínimo libre a cada lado del notch físico dentro del panel expandido.
    static let sideClearance: CGFloat = 212
    /// Ancho del vistazo actual (depende del texto).
    @Published var peekWidth: CGFloat = 0
    var peekSize: CGSize {
        CGSize(width: peekWidth, height: notchSize.height + Self.peekExtraHeight)
    }
    /// Tarjeta «AirPods conectados»: un panel más recogido y centrado que el de pestañas.
    var cardSize: CGSize {
        CGSize(width: max(440, notchSize.width + 250), height: 172)
    }

    var onHoverChange: ((Bool) -> Void)?
    var onExpandRequest: (() -> Void)?
    var onCollapseRequest: (() -> Void)?

    init(hasNotch: Bool, notchSize: CGSize, expandedSize: CGSize) {
        self.hasNotch = hasNotch
        self.notchSize = notchSize
        self.expandedSize = expandedSize
        peekWidth = notchSize.width + 220
    }

    func addToShelf(_ urls: [URL]) {
        for url in urls where !shelf.contains(url) {
            shelf.insert(url, at: 0)
        }
        if shelf.count > 12 {
            shelf.removeLast(shelf.count - 12)
        }
    }
}

// MARK: - Ventana

/// macOS "constriñe" cualquier ventana para que no invada la barra de menús,
/// empujándola hacia abajo. Este panel lo anula: tiene que vivir sobre el notch.
/// Además puede volverse "key" para que los botones reciban los clics, pero al ser
/// `.nonactivatingPanel` no roba el foco a la app que estés usando.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override var canBecomeKey: Bool { true }
}

/// Hace que el primer clic sobre el panel cuente (si no, macOS lo gasta solo en
/// "enfocar" la ventana y el botón no reacciona hasta el segundo clic) y fuerza el
/// cursor de flecha: el panel va por encima de la barra de menús y, sin esto, el
/// puntero desaparecía al pasar por el notch.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    private var cursorArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                                            .activeAlways, .enabledDuringMouseDrag],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        cursorArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }
}

final class NotchWindowController {
    private let panel: NSPanel
    private var hosting: NSHostingView<NotchView>?
    private let model: NotchModel
    private let media = MediaBridge()
    private let battery = BatteryMonitor()
    private let calendar = CalendarBridge()
    private let stats = SystemStats()
    private let sound: SoundFeature

    /// Plegado: exactamente el notch físico (ni un píxel más: durante el cambio de
    /// escritorio o sobre fondos claros, cualquier exceso de negro se vería).
    private let collapsedFrame: CGRect
    /// Zona en la que el ratón "cuenta" para abrir: algo más ancha que el notch.
    private let hoverZone: CGRect
    private let screenFrame: CGRect
    private let expandedFrame: CGRect
    /// Rectángulo del negro expandido en pantalla (sin margen de sombra).
    private let bodyFrame: CGRect
    private let shadowMargin: CGFloat
    private var collapseWork: DispatchWorkItem?
    private var expandWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var clickMonitor: Any?
    // Tap para reenviar al panel los clics de la franja superior (barra de menús),
    // que si no se los traga el sistema. Solo activo mientras está expandido.
    private var forwardTap: CFMachPort?
    private var forwardTapSource: CFRunLoopSource?
    /// Monitores de movimiento del ratón (global = sobre otras apps, local = sobre
    /// nuestro panel). Por eventos: cero despertares con el ratón quieto, al
    /// contrario que un temporizador sondeando la posición.
    private var moveMonitors: [Any] = []
    private var workspaceObservers: [Any] = []
    /// Vigilante de seguridad SOLO mientras está expandido, por si se pierde
    /// el evento de salida del ratón (p. ej. teletransporte del cursor).
    private var expandedWatchdog: Timer?
    /// Oculto porque la app en primer plano está a pantalla completa.
    private var hiddenForFullscreen = false

    var hideInFullscreen = true {
        didSet { refreshVisibility() }
    }
    var sneakPeekEnabled = true {
        didSet { updateWatch() }
    }
    var hideSystemBanner = true
    private var deviceWork: DispatchWorkItem?
    /// Tras un cambio de escritorio, nada se abre solo hasta que el ratón se mueva de verdad.
    private var expandBlockedUntilMouseMoves = false
    var showCoffee = true { didSet { model.showCoffee = showCoffee } }
    var showSettings = true { didSet { model.showSettings = showSettings } }
    var showBattery = true { didSet { model.showBattery = showBattery } }

    var enabledTabs: Set<NotchTab> = Set(NotchTab.allCases) {
        didSet {
            model.enabledTabs = enabledTabs
            if !enabledTabs.contains(model.tab),
               let first = NotchTab.allCases.first(where: { enabledTabs.contains($0) }) {
                model.tab = first
            }
        }
    }

    init(screen: NSScreen, keepAwake: KeepAwakeFeature, sound: SoundFeature) {
        self.sound = sound
        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = hasNotch
            ? screen.safeAreaInsets.top
            : max(30, screen.frame.maxY - screen.visibleFrame.maxY - 1)
        var notchWidth: CGFloat = 196
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }

        // A cada lado del notch físico deben caber las cinco pestañas de la izquierda
        // (16 + 5×32 + 4×6 + 8 = 208 pt) y el grupo de la derecha; así vale para
        // cualquier MacBook con notch, sea del ancho que sea.
        let expandedSize = CGSize(width: max(580, notchWidth + NotchModel.sideClearance * 2), height: 196)
        model = NotchModel(hasNotch: hasNotch,
                           notchSize: CGSize(width: notchWidth, height: notchHeight),
                           expandedSize: expandedSize)

        collapsedFrame = CGRect(x: screen.frame.midX - notchWidth / 2,
                                y: screen.frame.maxY - notchHeight,
                                width: notchWidth,
                                height: notchHeight)
        hoverZone = CGRect(x: collapsedFrame.minX - 20,
                           y: collapsedFrame.minY - 4,
                           width: notchWidth + 40,
                           height: notchHeight + 4)
        screenFrame = screen.frame
        // La ventana es más grande que el panel negro: el margen extra (lados y
        // abajo) deja sitio para que la sombra no se recorte. El borde superior sigue
        // pegado al techo de la pantalla para fundirse con el notch físico.
        let shadowMargin: CGFloat = 36
        self.shadowMargin = shadowMargin
        expandedFrame = CGRect(x: screen.frame.midX - (expandedSize.width + shadowMargin * 2) / 2,
                               y: screen.frame.maxY - expandedSize.height - shadowMargin,
                               width: expandedSize.width + shadowMargin * 2,
                               height: expandedSize.height + shadowMargin)
        // El negro visible (sin el margen de la sombra): es lo que cuenta para "salir".
        bodyFrame = CGRect(x: expandedFrame.minX + shadowMargin - NotchExpandedShape.flare,
                           y: expandedFrame.maxY - expandedSize.height,
                           width: expandedSize.width + NotchExpandedShape.flare * 2,
                           height: expandedSize.height)

        panel = NotchPanel(contentRect: collapsedFrame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Por encima de la barra de menús (capa 24) y de sus iconos (25): si no, ella
        // se dibuja sobre el notch y se lleva los clics. Va DESPUÉS de
        // `isFloatingPanel`, que reinicia el nivel a "flotante" (3).
        panel.level = .popUpMenu

        let hosting = FirstMouseHostingView(rootView: NotchView(model: model,
                                                                media: media,
                                                                battery: battery,
                                                                keepAwake: keepAwake,
                                                                calendar: calendar,
                                                                sound: sound,
                                                                stats: stats))
        panel.contentView = hosting
        self.hosting = hosting
        panel.setFrame(collapsedFrame, display: true)
        panel.orderFrontRegardless()
        AirDropPresenter.shared.sourceWindow = panel
        // Avisos «desplegando el notch» (Ajustes › Notch › Avisos).
        Toast.notchPresenter = { [weak self] text, symbol, duration, tint in
            self?.showMessage(text, symbol: symbol, duration: duration, tint: tint) ?? false
        }

        model.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }
        model.onExpandRequest = { [weak self] in self?.expandNow() }
        model.onCollapseRequest = { [weak self] in self?.collapseNow() }
        media.onTrackChange = { [weak self] info in self?.showPeek(for: info) }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.mouseMoved()
        }) {
            moveMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            moveMonitors.append(local)
        }

        // Cambios de escritorio y de app en primer plano: recolocar el panel (algunas
        // transiciones lo dejan atrás) y decidir si toca esconderse por pantalla completa.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                // Al cambiar de escritorio, el panel abierto se quedaba quieto mientras todo
                // se deslizaba: se pliega en el acto y no se reabre hasta que muevas el ratón.
                if note.name == NSWorkspace.activeSpaceDidChangeNotification { self.collapseForSpaceChange() }
                self.refreshVisibility()
            })
        }
        refreshVisibility()
        updateWatch()
    }

    func close() {
        Toast.notchPresenter = nil
        media.stopPolling()
        media.stopWatching()
        removeClickMonitor()
        removeForwardingTap()
        stopWatchdog()
        cancelExpand()
        peekWork?.cancel()
        moveMonitors.forEach { NSEvent.removeMonitor($0) }
        moveMonitors = []
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        panel.orderOut(nil)
    }

    /// `CGRect.contains` excluye el borde superior, y en el techo de la pantalla el
    /// ratón devuelve exactamente y = maxY: la zona se prolonga hacia arriba para que
    /// "subir del todo" cuente como estar dentro (antes no abría o se cerraba).
    private static func reaches(_ rect: CGRect, _ point: CGPoint) -> Bool {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 60).contains(point)
    }

    /// Reacciona al movimiento del ratón: expande al entrar en la zona del notch
    /// y programa el plegado al salir del panel expandido.
    private func mouseMoved() {
        guard !hiddenForFullscreen else { return }
        expandBlockedUntilMouseMoves = false
        let mouse = NSEvent.mouseLocation
        if model.expanded {
            updateHover(screenPoint: mouse)
            if model.deviceCard != nil { return }   // la tarjeta se cierra sola
            // Fuera del negro (6 px de margen) → se pliega casi al instante.
            if Self.reaches(bodyFrame.insetBy(dx: -6, dy: -6), mouse) {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.collapseNow() }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
            }
        } else if Self.reaches(hoverZone, mouse) {
            scheduleExpand()
        } else {
            cancelExpand()
        }
    }

    /// Estado de reposo (plegado): el notch exacto e invisible.
    private func applyRestingState() {
        guard !model.expanded, model.peek == nil else { return }
        panel.setFrame(collapsedFrame, display: true)
        setBlack(false)
    }

    // MARK: - Expandir / plegar

    private func hoverChanged(_ hovering: Bool) {
        if hovering {
            scheduleExpand()
        } else if model.expanded, collapseWork == nil, model.deviceCard == nil {
            // margen para mover el ratón dentro del panel sin que se cierre
            let work = DispatchWorkItem { [weak self] in self?.collapseNow() }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
        // Al salir NO cancelamos una apertura programada: el temporizador vuelve a
        // comprobar dónde está el ratón (las salidas espurias del área de seguimiento
        // dejaban el notch sin abrirse).
    }

    /// Un instante encima del notch antes de abrir (ajustable en Ajustes): así no se
    /// despliega solo al pasar el ratón de largo por la zona.
    private func scheduleExpand() {
        guard !model.expanded, expandWork == nil, !hiddenForFullscreen, !expandBlockedUntilMouseMoves else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            if Self.reaches(self.hoverZone, NSEvent.mouseLocation) {
                self.expandNow()
            }
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchSettings.hoverDelay, execute: work)
    }

    private func cancelExpand() {
        expandWork?.cancel()
        expandWork = nil
    }

    private func expandNow() {
        collapseWork?.cancel()
        collapseWork = nil
        cancelExpand()
        guard !model.expanded, !hiddenForFullscreen else { return }
        // Vibración del trackpad al abrirse (intensidad configurable en Ajustes).
        NotchHaptics.play()

        // Si estaba el vistazo rápido, fuera sin animación: lo sustituye la apertura.
        peekWork?.cancel()
        peekWork = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.peek = nil }

        // El negro aparece ya (sin animar): el primer fotograma lo tapa el notch físico.
        setBlack(true)
        // 1º agrandamos la ventana (invisible: la forma sigue plegada y centrada) y
        // forzamos el layout; 2º, ya en el siguiente ciclo, animamos la forma. Si ambas
        // cosas ocurren en el mismo ciclo, el primer fotograma sale anclado a un lado y
        // la apertura parece crecer desde el lateral en vez de desde el centro.
        panel.setFrame(expandedFrame, display: true)
        panel.layoutIfNeeded()
        panel.orderFrontRegardless()
        // No forzamos "key" al pasar el ratón para no robar el foco del teclado a la app
        // que estés usando: `acceptsFirstMouse` ya hace que el primer clic en un botón cuente.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.model.expanded else { return }
            // mismo muelle que el plegado, para que entrada y salida se sientan iguales
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                self.model.expanded = true
            }
            // El contenido aparece cuando el negro ya casi tiene su tamaño.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.model.expanded else { return }
                withAnimation(.easeOut(duration: 0.25)) { self.model.showContent = true }
            }
        }
        media.stopWatching()
        media.startPolling()
        battery.refresh()
        installClickMonitor()
        installForwardingTap()
        startWatchdog()
    }

    private func collapseNow() {
        collapseWork?.cancel()
        collapseWork = nil
        guard model.expanded else { return }

        withAnimation(.easeIn(duration: 0.1)) { model.showContent = false }
        // Plegado un poco más ágil que la apertura. El reencuadre del panel (estado de
        // reposo) se hace cuando el muelle ha terminado de verdad (`completion`), no
        // tras un retardo fijo: así nunca recortamos la animación si un fotograma llega
        // tarde y no hay que ajustar el retardo a mano si se cambia el muelle.
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9), completionCriteria: .removed) {
            model.expanded = false
        } completion: { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.model.deviceCard = nil }
            self.applyRestingState()   // no hace nada si se ha vuelto a abrir mientras tanto
        }
        model.hover.point = nil
        media.stopPolling()
        removeClickMonitor()
        removeForwardingTap()
        stopWatchdog()
        updateWatch()
    }

    /// Plegado inmediato (sin animación) al cambiar de escritorio.
    private func collapseForSpaceChange() {
        cancelExpand()
        collapseWork?.cancel(); collapseWork = nil
        deviceWork?.cancel(); deviceWork = nil
        peekWork?.cancel(); peekWork = nil
        expandBlockedUntilMouseMoves = true
        guard model.expanded || model.peek != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.showContent = false
            model.expanded = false
            model.deviceCard = nil
            model.peek = nil
        }
        model.hover.point = nil
        media.stopPolling()
        removeClickMonitor()
        removeForwardingTap()
        stopWatchdog()
        updateWatch()
        applyRestingState()
    }

    // MARK: - Auriculares conectados

    /// Despliega el notch con la tarjeta del dispositivo y lo pliega solo pasados unos
    /// segundos (si el ratón está dentro, se queda abierto con las pestañas normales).
    func presentHeadphones(_ info: HeadphonesInfo) {
        guard !hiddenForFullscreen else { return }
        if hideSystemBanner { SystemBannerDismisser.dismissSoon() }
        deviceWork?.cancel()
        if model.expanded {
            // Ya abierto por el usuario: la tarjeta sustituye a las pestañas un momento.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.deviceCard = info }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.deviceCard = info }
            expandNow()
        }
        scheduleHeadphonesDismiss(after: 3.2)
    }

    /// Llega la batería: se actualiza la tarjeta (los anillos entran animados).
    func updateHeadphones(_ info: HeadphonesInfo) {
        guard model.deviceCard != nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { model.deviceCard = info }
        scheduleHeadphonesDismiss(after: 2.2)
    }

    private func scheduleHeadphonesDismiss(after seconds: TimeInterval) {
        deviceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissHeadphones() }
        deviceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func dismissHeadphones() {
        deviceWork = nil
        guard model.deviceCard != nil else { return }
        if Self.reaches(bodyFrame.insetBy(dx: -6, dy: -6), NSEvent.mouseLocation) {
            withAnimation(.easeInOut(duration: 0.25)) { model.deviceCard = nil }
        } else {
            collapseNow()
        }
    }

    /// Cambia la visibilidad del negro sin animación (ver `NotchModel.blackVisible`).
    private func setBlack(_ visible: Bool) {
        guard model.blackVisible != visible else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.blackVisible = visible }
    }

    // MARK: - Pantalla completa y escritorios

    /// Con una app a pantalla completa delante, el notch se esconde (si así está
    /// configurado); si no, se asegura de estar visible y por encima.
    private func refreshVisibility() {
        let shouldHide = hideInFullscreen && Self.frontmostIsFullscreen()
        if shouldHide != hiddenForFullscreen {
            hiddenForFullscreen = shouldHide
            if shouldHide {
                cancelExpand()
                if model.expanded { collapseNow() }
                hidePeek()
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
            updateWatch()
        } else if !shouldHide {
            panel.orderFrontRegardless()
        }
    }

    private static func frontmostIsFullscreen() -> Bool {
        let myPID = NSRunningApplication.current.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != myPID,
              Permissions.hasAccessibility else { return false }
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute as String)
                ?? AX.element(axApp, kAXMainWindowAttribute as String) else { return false }
        return AX.bool(window, "AXFullScreen")
    }

    // MARK: - Vistazo rápido

    /// Vigilancia de la música solo cuando hace falta: plegado, visible y con el
    /// vistazo rápido activado.
    private func updateWatch() {
        if sneakPeekEnabled && !model.expanded && !hiddenForFullscreen {
            media.startWatching()
        } else {
            media.stopWatching()
        }
    }

    private func showPeek(for info: NowPlayingInfo) {
        guard sneakPeekEnabled else { return }
        presentPeek(PeekInfo(symbol: "music.note", title: info.title, subtitle: info.artist, tint: nil), duration: 3.2)
    }

    /// Un aviso cualquiera bajo el notch (estilo «desplegando el notch»).
    private func showMessage(_ text: String, symbol: String, duration: TimeInterval, tint: NSColor?) -> Bool {
        guard !hiddenForFullscreen, !model.expanded else { return false }
        presentPeek(PeekInfo(symbol: symbol, title: text, subtitle: "", tint: tint), duration: duration)
        return true
    }

    /// Marco del vistazo, centrado bajo el notch y tan ancho como pida el texto.
    private var peekFrame: CGRect {
        let size = model.peekSize
        return CGRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    private func presentPeek(_ info: PeekInfo, duration: TimeInterval) {
        guard !model.expanded, !hiddenForFullscreen else { return }
        peekWork?.cancel()
        // Ancho según el texto (con un mínimo y sin salirse de la pantalla).
        let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let subtitleFont = NSFont.systemFont(ofSize: 11.5)
        var textWidth = (info.title as NSString).size(withAttributes: [.font: titleFont]).width
        if !info.subtitle.isEmpty {
            textWidth += ("· " + info.subtitle as NSString).size(withAttributes: [.font: subtitleFont]).width + 6
        }
        let extras: CGFloat = 20 + 12 + (info.tint == nil ? 0 : 22) + (NotchExpandedShape.flare + 12) * 2 + 16
        let width = min(max(model.notchSize.width + 110, textWidth + extras), screenFrame.width - 80)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.peekWidth = width }
        setBlack(true)
        panel.setFrame(peekFrame, display: true)
        panel.layoutIfNeeded()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.model.expanded else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.model.peek = info
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.hidePeek() }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func hidePeek() {
        peekWork?.cancel()
        peekWork = nil
        guard model.peek != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) { model.peek = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.applyRestingState()
        }
    }

    /// Un clic fuera del panel lo pliega al instante.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.expanded else { return }
            if !Self.reaches(self.panel.frame, NSEvent.mouseLocation) {
                self.collapseNow()
            }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    /// Traduce la posición del ratón a coordenadas del hosting view (origen
    /// arriba-izquierda) para los efectos hover del reproductor.
    private func updateHover(screenPoint: CGPoint) {
        guard let hosting else { return }
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let viewPoint = hosting.convert(windowPoint, from: nil)
        if model.hover.point != viewPoint {
            model.hover.point = viewPoint
        }
    }

    // MARK: - Reenvío de clics de la franja superior

    private func installForwardingTap() {
        guard forwardTap == nil, Permissions.hasAccessibility else { return }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                 | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<NotchWindowController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handleForwardedClick(type: type, event: event)
        }, userInfo: refcon) else { return }
        forwardTap = tap
        forwardTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), forwardTapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeForwardingTap() {
        // Invalidar, no solo soltar: el sistema conserva el puerto del tap hasta que
        // se invalida, y sin esto cada apertura del notch dejaba un puerto Mach y una
        // fuente del run loop huérfanos.
        if let forwardTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), forwardTapSource, .commonModes)
            CFRunLoopSourceInvalidate(forwardTapSource)
        }
        if let forwardTap {
            CGEvent.tapEnable(tap: forwardTap, enable: false)
            CFMachPortInvalidate(forwardTap)
        }
        forwardTapSource = nil
        forwardTap = nil
    }

    fileprivate func handleForwardedClick(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let forwardTap { CGEvent.tapEnable(tap: forwardTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard model.expanded else { return Unmanaged.passUnretained(event) }

        let loc = event.location // global, origen arriba-izquierda
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let f = panel.frame
        let cgPanelTop: CGFloat = primaryH - f.maxY           // 0 si está pegado al techo
        let stripHeight = model.notchSize.height + 16          // franja de la barra de menús + margen

        // Solo la franja superior dentro del cuerpo visible del panel (sin el margen
        // de la sombra); el resto pasa normal (ya funciona).
        let flare = NotchExpandedShape.flare
        let bodyMinX = f.minX + shadowMargin - flare
        let bodyMaxX = f.maxX - shadowMargin + flare
        guard bodyMinX...bodyMaxX ~= loc.x, loc.y >= cgPanelTop, loc.y < cgPanelTop + stripHeight else {
            return Unmanaged.passUnretained(event)
        }

        let cocoaPoint = CGPoint(x: loc.x, y: primaryH - loc.y)
        let windowPoint = panel.convertPoint(fromScreen: cocoaPoint)
        let nsType: NSEvent.EventType = (type == .leftMouseDown) ? .leftMouseDown : .leftMouseUp
        if let ns = NSEvent.mouseEvent(with: nsType,
                                       location: windowPoint,
                                       modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber,
                                       context: nil,
                                       eventNumber: 0,
                                       clickCount: 1,
                                       pressure: nsType == .leftMouseDown ? 1 : 0) {
            panel.sendEvent(ns)
        }
        return nil // consumimos: la barra de menús no debe actuar
    }

    private func startWatchdog() {
        guard expandedWatchdog == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.model.expanded else { return }
            if self.model.deviceCard != nil { return }   // la tarjeta se cierra sola
            if !Self.reaches(self.bodyFrame.insetBy(dx: -16, dy: -16), NSEvent.mouseLocation) {
                self.collapseNow()
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        expandedWatchdog = timer
    }

    private func stopWatchdog() {
        expandedWatchdog?.invalidate()
        expandedWatchdog = nil
    }
}
