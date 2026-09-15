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
    static let shortcut = ShortcutBinding(key: "menuBar.toggle", hotKeyID: 600,
                                          title: L("Enseñar u ocultar los iconos", "Show or hide the icons"),
                                          fallback: Shortcut(kVK_ANSI_B, controlKey | optionKey | cmdKey))

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
        guard UserDefaults.standard.bool(forKey: "feature.menubar.enabled") else { return }
        placeOwnIcons(force: false)
    }

    /// Nuestros iconos, a la derecha de la línea **y en su orden**.
    ///
    /// Antes solo se miraba que estuvieran a la derecha de la línea, no en qué orden:
    /// macOS reescribe estas posiciones cada vez que aparece un icono nuevo y la
    /// gráfica de rendimiento acababa colada entre la línea y la flecha, donde nada
    /// de lo que sueltes se esconde. Si uno se sale de la fila, vuelve a ella y los de
    /// su derecha se corren; el orden es el de `arrangement`.
    ///
    /// **La línea no se mueve nunca.** Es el límite que ha puesto la persona
    /// arrastrando sus iconos a un lado o a otro: devolverla a la posición de fábrica
    /// destapaba de golpe todo lo que hubiera escondido entre medias.
    ///
    /// - Parameter force: recoloca todos los nuestros (el botón «Recolocar»). Sin
    ///   ello solo se tocan los que se hayan salido de sitio.
    @discardableResult
    private static func placeOwnIcons(force: Bool) -> Bool {
        let defaults = UserDefaults.standard
        func position(_ name: String) -> Double? {
            (defaults.object(forKey: positionKey(name)) as? NSNumber)?.doubleValue
        }

        let line = arrangement[0].name
        let limit = position(line) ?? Double(arrangement[0].position)
        if position(line) == nil { defaults.set(limit, forKey: positionKey(line)) }

        let names = ownIconNames
        let current = names.reduce(into: [String: Double]()) { $0[$1] = position($1) }
        let moves = placements(for: names, current: current, limit: limit, force: force)
        for (name, value) in moves {
            defaults.set(value, forKey: positionKey(name))
        }
        return !moves.isEmpty
    }

    /// Recoloca los iconos de OmniMac si alguno se ha ido de sitio, y los rehace.
    ///
    /// Arrastrando la línea se puede dejar la **flecha** a su izquierda, y entonces el
    /// escondedor se traga su propio botón de rescate: los iconos desaparecen y no hay
    /// dónde pulsar para recuperarlos. Antes eso duraba hasta el siguiente arranque.
    /// Ahora, en cuanto se pide abrir o cerrar —con la flecha, con el atajo o desde
    /// Ajustes—, se comprueba y se arregla. Si está todo en su sitio no se toca nada:
    /// rehacer los iconos parpadea.
    private func healIfNeeded() {
        guard isEnabled, Self.someIconIsSwallowed() else { return }
        Self.placeOwnIcons(force: false)
        stop()
        start()
    }

    /// ¿Se está tragando el escondedor algún icono nuestro?
    ///
    /// Es lo único que justifica rehacer los iconos en caliente. Que estén algo
    /// desordenados se arregla al arrancar y no molesta a nadie; que la **flecha**
    /// quede a la izquierda de la línea sí, porque entonces desaparece con los demás
    /// y no queda dónde pulsar para recuperarlos.
    private static func someIconIsSwallowed() -> Bool {
        let defaults = UserDefaults.standard
        func position(_ name: String) -> Double? {
            (defaults.object(forKey: positionKey(name)) as? NSNumber)?.doubleValue
        }
        guard let limit = position(arrangement[0].name) else { return true }   // sin línea, a recolocar
        let current = ownIconNames.reduce(into: [String: Double]()) { $0[$1] = position($1) }
        return swallowed(positions: current, names: ownIconNames, limit: limit)
    }

    /// Fuera de UserDefaults para poder probarlo: a más número, más a la izquierda,
    /// así que un icono nuestro con posición mayor o igual que la línea está perdido.
    static func swallowed(positions: [String: Double], names: [String], limit: Double) -> Bool {
        names.contains { name in
            guard let position = positions[name] else { return true }   // sin posición, se recoloca
            return position >= limit
        }
    }

    static func positionKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// Nuestros iconos de izquierda a derecha, sin la línea (que no se mueve).
    static var ownIconNames: [String] {
        arrangement.dropFirst().map(\.name) + ModuleIcons.available.map { "omnimac.module.\($0)" }
    }

    /// Hueco entre dos iconos nuestros.
    private static let spacing: Double = 18

    /// Qué iconos hay que mover y adónde, dadas las posiciones que tienen ahora.
    ///
    /// Fuera de UserDefaults y de la barra a propósito: así se puede probar en
    /// `swift test` lo que aquí se fue de las manos sin que nadie lo viera —un icono
    /// colado entre la línea y la flecha—. Devuelve **solo los que hay que mover**;
    /// los que ya están en su sitio ni se tocan.
    static func placements(for names: [String], current: [String: Double],
                           limit: Double, force: Bool) -> [String: Double] {
        var result: [String: Double] = [:]
        var next = limit - spacing
        for name in names {
            // Ya está a la derecha del anterior: se respeta y se sigue desde ahí.
            if !force, let position = current[name], position <= next {
                next = position - spacing
                continue
            }
            result[name] = next
            next -= spacing
        }
        return result
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

        HotKeyCenter.shared.bind(Self.shortcut) { [weak self] in self?.toggle() }
        apply()
    }

    override func stop() {
        HotKeyCenter.shared.unbind(Self.shortcut)
        autoHideWork?.cancel()
        autoHideWork = nil
        // Al quitar un NSStatusItem, AppKit **borra** su posición guardada. Sin
        // devolverla, la línea y la flecha reaparecen donde macOS quiera: era lo que
        // hacía que los iconos pegaran un salto al pulsar la flecha, y de paso se
        // perdía el límite que el usuario había colocado a mano.
        let guardadas = Self.savedPositions(of: Self.arrangement.prefix(2).map(\.name))
        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        if let expander { NSStatusBar.system.removeStatusItem(expander) }
        Self.restore(guardadas)
        self.separator = nil
        self.expander = nil
    }

    /// Las posiciones guardadas de unos iconos, para poder devolverlas.
    static func savedPositions(of names: [String]) -> [String: Double] {
        names.reduce(into: [:]) { result, name in
            if let value = (UserDefaults.standard.object(forKey: positionKey(name)) as? NSNumber)?.doubleValue {
                result[name] = value
            }
        }
    }

    static func restore(_ positions: [String: Double]) {
        for (name, value) in positions { UserDefaults.standard.set(value, forKey: positionKey(name)) }
    }

    /// Devuelve los iconos de OmniMac a su sitio, sin tocar la línea.
    ///
    /// Hace falta porque macOS recuerda dónde dejó el usuario cada icono, y basta un
    /// arrastre desafortunado para que el de OmniMac acabe entre la línea y la
    /// flecha: entonces lo que sueltes ahí en medio no se esconde y parece que la
    /// función está rota.
    func rearrange() {
        Self.placeOwnIcons(force: true)
        // Las posiciones se leen al crear cada icono, así que hay que rehacerlos.
        guard isEnabled else { return }
        stop()
        start()
    }

    // MARK: - Abrir y cerrar

    func toggle() {
        healIfNeeded()
        collapsed.toggle()
    }

    func expand() {
        guard collapsed else { return }
        healIfNeeded()
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
