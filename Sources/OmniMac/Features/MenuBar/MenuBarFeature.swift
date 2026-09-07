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
    /// Cuando está desplegado el expansor casi no ocupa, para no dejar un hueco raro.
    private static let restWidth: CGFloat = 1

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

        let expander = NSStatusBar.system.statusItem(withLength: Self.restWidth)
        expander.autosaveName = "com.seergiii.omnimac.menubar.expander"
        // Sin imagen ni acción: es solo espacio. Si tuviera acción, pulsar en
        // cualquier hueco de la barra haría algo, y eso desconcierta.
        expander.button?.image = nil
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
        expander?.length = collapsed ? Self.pushWidth : Self.restWidth
        let symbol = collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: collapsed
                                ? L("Mostrar los iconos escondidos", "Show hidden icons")
                                : L("Esconder los iconos", "Hide the icons"))
        image?.isTemplate = true
        separator?.button?.image = image
        scheduleAutoHide()
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
