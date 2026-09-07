import AppKit
import Carbon.HIToolbox
import Combine

/// Esconde los iconos de la barra de menús que no usas a diario.
///
/// La técnica no tiene misterio ni usa APIs privadas ni permisos: OmniMac pone dos
/// iconos propios en la barra y se aprovecha de que macOS los coloca de derecha a
/// izquierda. El **expansor** es un icono invisible que, al hacerse enormemente
/// ancho, empuja fuera de la pantalla todo lo que tiene a su izquierda; al
/// devolverle su ancho normal, los iconos vuelven a aparecer. El **separador** es
/// la flecha en la que pulsas para abrir y cerrar.
///
/// Quién se esconde lo decides tú una sola vez: mantén ⌘ y arrastra los iconos que
/// quieras ocultar a la izquierda de la flecha. macOS recuerda esas posiciones.
final class MenuBarFeature: BaseFeature {
    static let toggleHotKey: UInt32 = 600

    /// Ancho al que crece el expansor. Cualquier cosa mayor que la pantalla vale:
    /// lo que sobra se sale por la izquierda, que es justo lo que queremos.
    private static let pushWidth: CGFloat = 10_000
    /// Ancho de la barrita que marca el límite cuando los iconos están a la vista.
    private static let dividerWidth: CGFloat = 10

    /// ¿Están los iconos escondidos ahora mismo?
    @Published private(set) var collapsed: Bool {
        didSet {
            UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
            apply()
        }
    }

    /// Volver a esconderlos solos pasado un rato.
    @Published var autoHide: Bool {
        didSet {
            UserDefaults.standard.set(autoHide, forKey: "menubar.autoHide")
            scheduleAutoHide()
        }
    }

    /// Segundos que tardan en volver a esconderse.
    @Published var autoHideDelay: Double {
        didSet {
            UserDefaults.standard.set(autoHideDelay, forKey: "menubar.autoHideDelay")
            scheduleAutoHide()
        }
    }

    static let collapsedKey = "menubar.collapsed"

    /// Colocación de los tres iconos de OmniMac, en «distancia al borde derecho»
    /// (a más número, más a la izquierda): línea, flecha y el icono de OmniMac, que
    /// se queda a la derecha de la flecha para no esconderse nunca.
    private static let arrangement: [(name: String, position: Int)] = [
        ("com.seergiii.omnimac.menubar.expander", 380),
        ("com.seergiii.omnimac.menubar.separator", 362),
        (StatusItemController.autosaveName, 340),
        (MenuBarStats.autosaveName, 330),
    ]

    /// Ningún icono de OmniMac puede quedar a la izquierda de la línea.
    ///
    /// macOS reescribe estas posiciones por su cuenta cada vez que aparece un icono
    /// nuevo, y con eso los nuestros acababan a la izquierda del límite: el
    /// escondedor se tragaba la app entera, la flecha para recuperarla incluida. Al
    /// arrancar se comprueban los nuestros y se devuelven a la derecha; los de otras
    /// apps no se tocan, que esos los coloca el usuario.
    ///
    /// Hay que llamarlo **antes** de crear ningún icono: AppKit lee la posición al
    /// crearlo, no después. Y los valores se leen como decimales, que es como los
    /// guarda macOS; leyéndolos como enteros no se reconocía ninguno.
    static func ensureOwnIconsVisible() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "feature.menubar.enabled") else { return }

        func key(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }
        func position(_ name: String) -> Double? {
            (defaults.object(forKey: key(name)) as? NSNumber)?.doubleValue
        }

        let limit = position(arrangement[0].name) ?? Double(arrangement[0].position)

        // De izquierda a derecha, en el orden en que los queremos ver.
        var names = [arrangement[1].name, arrangement[2].name, arrangement[3].name]
        names += ModuleIcons.available.map { "omnimac.module.\($0)" }

        var next = limit - 18
        for name in names {
            if let current = position(name), current < limit {
                next = min(next, current - 18)   // ya estaba a la derecha: se respeta
                continue
            }
            defaults.set(next, forKey: key(name))
            next -= 18
        }
    }

    /// Sitio de la gráfica de rendimiento, a la derecha de la flecha para que el
    /// propio escondedor no se la trague.
    static let statsPosition = 330

    private var separator: NSStatusItem?
    private var expander: NSStatusItem?
    private var autoHideWork: DispatchWorkItem?

    init() {
        let defaults = UserDefaults.standard
        collapsed = defaults.object(forKey: Self.collapsedKey) == nil ? true : defaults.bool(forKey: Self.collapsedKey)
        autoHide = defaults.object(forKey: "menubar.autoHide") == nil ? true : defaults.bool(forKey: "menubar.autoHide")
        autoHideDelay = defaults.object(forKey: "menubar.autoHideDelay") == nil ? 15 : defaults.double(forKey: "menubar.autoHideDelay")
        super.init(id: "menubar",
                   name: L("Barra de menús", "Menu bar"),
                   symbol: "menubar.arrow.up.rectangle",
                   blurb: L("Esconde los iconos que no usas a diario y recupera sitio en la barra.",
                            "Hide the icons you don't use every day and get the space back."),
                   defaultEnabled: false)
    }

    override func start() {
        // El orden importa: macOS pone cada icono nuevo a la izquierda del anterior,
        // así que el expansor queda a la izquierda del separador, que es donde tiene
        // que estar para empujar a los demás.
        let separator = NSStatusBar.system.statusItem(withLength: 24)
        separator.autosaveName = "com.seergiii.omnimac.menubar.separator"
        separator.button?.target = self
        separator.button?.action = #selector(separatorClicked)
        separator.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        separator.button?.toolTip = L("Mostrar u ocultar los iconos de la izquierda",
                                      "Show or hide the icons on the left")
        self.separator = separator

        let expander = NSStatusBar.system.statusItem(withLength: Self.dividerWidth)
        expander.autosaveName = "com.seergiii.omnimac.menubar.expander"
        // El expansor es el límite de verdad, así que se ve: una barrita. Antes era
        // invisible y el usuario se guiaba por la flecha, que está a su derecha; lo
        // que arrastrara entre las dos no se escondía nunca.
        expander.button?.image = Self.dividerImage()
        expander.button?.toolTip = L("Todo lo que quede a la izquierda de esta línea se esconde",
                                     "Everything to the left of this line gets hidden")
        // Sin acción: es una marca, no un botón.
        expander.button?.isEnabled = false
        self.expander = expander

        HotKeyCenter.shared.register(id: Self.toggleHotKey,
                                     keyCode: UInt32(kVK_ANSI_B),
                                     modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.toggle()
        }
        apply()
    }

    override func stop() {
        HotKeyCenter.shared.unregister(id: Self.toggleHotKey)
        autoHideWork?.cancel()
        autoHideWork = nil
        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        if let expander { NSStatusBar.system.removeStatusItem(expander) }
        self.separator = nil
        self.expander = nil
    }

    /// Devuelve los tres iconos de OmniMac a su sitio.
    ///
    /// Hace falta porque macOS recuerda dónde dejó el usuario cada icono, y basta un
    /// arrastre desafortunado para que el de OmniMac acabe entre la línea y la
    /// flecha: entonces lo que sueltes ahí en medio no se esconde y parece que la
    /// función está rota.
    func rearrange() {
        for item in Self.arrangement {
            UserDefaults.standard.set(item.position, forKey: "NSStatusItem Preferred Position \(item.name)")
        }
        // Las posiciones se leen al crear cada icono, así que hay que rehacerlos.
        guard isEnabled else { return }
        stop()
        start()
    }

    // MARK: - Abrir y cerrar

    func toggle() {
        collapsed.toggle()
    }

    func expand() {
        guard collapsed else { return }
        collapsed = false
    }

    func collapse() {
        guard !collapsed else { return }
        collapsed = true
    }

    @objc private func separatorClicked() {
        // Con el botón derecho, el menú de siempre; con el izquierdo, abrir/cerrar.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: L("Ajustes de la barra…", "Menu bar settings…"),
                                  action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let hint = NSMenuItem(title: L("Mantén ⌘ y arrastra los iconos a la izquierda de la flecha para esconderlos",
                                       "Hold ⌘ and drag icons to the left of the arrow to hide them"),
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        separator?.menu = menu
        separator?.button?.performClick(nil)
        separator?.menu = nil
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Lleva el estado a los iconos de la barra.
    private func apply() {
        expander?.length = collapsed ? Self.pushWidth : Self.dividerWidth
        let symbol = collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: collapsed
                                ? L("Mostrar los iconos escondidos", "Show hidden icons")
                                : L("Esconder los iconos", "Hide the icons"))
        image?.isTemplate = true
        separator?.button?.image = image
        scheduleAutoHide()
    }

    /// La marca del límite: una barrita vertical discreta.
    private static func dividerImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 3, height: 13), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.midX - 0.75, y: 0, width: 1.5, height: rect.height),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("Límite: lo que quede a la izquierda se esconde",
                                           "Boundary: anything to the left gets hidden")
        return image
    }

    /// Cuando se abre, se vuelve a cerrar solo pasado el rato configurado.
    private func scheduleAutoHide() {
        autoHideWork?.cancel()
        autoHideWork = nil
        guard isEnabled, autoHide, !collapsed, autoHideDelay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.autoHideWork = nil
            self?.collapse()
        }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
    }
}
