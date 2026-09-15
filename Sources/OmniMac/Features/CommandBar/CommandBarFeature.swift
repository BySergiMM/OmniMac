import AppKit
import Carbon.HIToolbox

/// Un comando del buscador.
struct Command: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    /// Palabras extra por las que también se encuentra («micro» para el micrófono,
    /// y el nombre del módulo, para que «utilidades» enseñe las utilidades).
    let keywords: String
    let run: () -> Void

    /// Lo que se busca: el título más las palabras extra.
    var searchable: String { keywords.isEmpty ? title : "\(title) \(keywords)" }
}

/// Buscador de comandos: ⌥Espacio y escribes lo que quieres hacer.
///
/// La gracia no es tener otro lanzador de apps, es que **todo lo que hace OmniMac
/// se puede hacer escribiendo**, sin recordar ocho atajos ni buscar en los ajustes.
/// Las apps instaladas van después, como red de seguridad.
///
/// El índice de apps se construye **al abrir el panel y en segundo plano**, y se
/// tira al cerrarlo: recorrer las carpetas de aplicaciones cuesta —lo bastante como
/// para que el panel tardara en aparecer— y no hay ninguna razón para tenerlo en
/// memoria mientras nadie busca.
final class CommandBarFeature: BaseFeature {
    /// ⌥Espacio de fábrica, y por eso el módulo viene apagado: es el atajo de
    /// Raycast y de Alfred. Ahora se puede cambiar, así que encenderlo ya no obliga
    /// a elegir entre una cosa y otra.
    static let shortcut = ShortcutBinding(key: "commandBar.toggle", hotKeyID: 700,
                                          title: L("Abrir el buscador de comandos", "Open the command bar"),
                                          fallback: Shortcut(kVK_Space, optionKey))

    private let panel = CommandBarPanelController()
    // Solo los módulos que necesita, no el gestor entero: así no hay ciclo y se ve
    // de un vistazo sobre qué puede actuar.
    private unowned let keepAwake: KeepAwakeFeature
    private unowned let tools: ToolsFeature
    private unowned let clipboard: ClipboardFeature
    private unowned let sound: SoundFeature

    init(keepAwake: KeepAwakeFeature, tools: ToolsFeature,
         clipboard: ClipboardFeature, sound: SoundFeature) {
        self.keepAwake = keepAwake
        self.tools = tools
        self.clipboard = clipboard
        self.sound = sound
        super.init(id: "commandbar",
                   name: L("Buscador de comandos", "Command bar"),
                   symbol: "command",
                   blurb: L("⌥Espacio y escribe: cualquier función de OmniMac y cualquier app, sin recordar atajos.",
                            "⌥Space and type: any OmniMac feature and any app, without remembering shortcuts."),
                   // Apagado de fábrica **a propósito**: ⌥Espacio es el atajo de
                   // Raycast y de Alfred, y quitárselo a alguien sin avisar el primer
                   // día es la clase de cosa que hace desinstalar una app.
                   defaultEnabled: false)
        panel.onRun = { [weak self] command in
            self?.panel.hide()
            // Se ejecuta cuando la app que estaba delante ha recuperado el foco: si
            // no, cosas como pegar irían al panel que se está cerrando.
            Self.whenFocusIsBack { command.run() }
        }
    }

    override func start() {
        HotKeyCenter.shared.bind(Self.shortcut) { [weak self] in self?.toggle() }
    }

    override func stop() {
        HotKeyCenter.shared.unbind(Self.shortcut)
        panel.hide()
    }

    func toggle() {
        if panel.isVisible { return panel.hide() }
        // Las funciones de OmniMac ya, y las apps en cuanto estén: recorrer las
        // carpetas tarda, y hacerlo antes de enseñar el panel hacía que el atajo
        // pareciera muerto.
        panel.show(commands: omniMacCommands())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = Self.applications()
            DispatchQueue.main.async { self?.panel.add(apps) }
        }
    }

    /// Espera a que vuelva el foco antes de ejecutar.
    ///
    /// Casi siempre el panel no roba el foco a nadie y esto es inmediato. Cuando sí
    /// —el botón «Probar» de Ajustes—, la activación de la otra app tarda, y un
    /// retardo fijo de 50 ms se quedaba corto: el ⌘V de «pegar sin formato» acababa
    /// en la ventana equivocada.
    private static func whenFocusIsBack(_ work: @escaping () -> Void) {
        func weAreStillInFront() -> Bool {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard weAreStillInFront() else { return work() }
            var done = false
            var token: NSObjectProtocol?
            let finish = {
                guard !done else { return }
                done = true
                if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
                work()
            }
            token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main) { _ in finish() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { finish() }
        }
    }

    // MARK: - El índice

    /// Todo lo que sabe hacer OmniMac **y está encendido**, en una lista.
    ///
    /// Los módulos apagados no salen: ofrecer «Historial del portapapeles» con el
    /// portapapeles apagado abría un panel vacío, y «Mantener el Mac despierto»
    /// llegaba a dejar el Mac despierto sin nada en el menú con lo que pararlo.
    private func omniMacCommands() -> [Command] {
        // Copias locales para que las clausuras no capturen `self`: el buscador
        // puede desaparecer entre que se abre el panel y se pulsa Intro.
        let keepAwake = self.keepAwake, tools = self.tools
        let clipboard = self.clipboard, sound = self.sound
        var list: [Command] = []

        /// - Parameter area: el módulo. Sale en el subtítulo y también se busca.
        /// - Parameter shortcut: de dónde leer el atajo que se enseña. Antes estaban
        ///   escritos a mano («⇧⌘2») y mentían en cuanto los cambiabas en Ajustes.
        func add(_ id: String, _ title: String, _ area: String, _ symbol: String,
                 _ keywords: String = "", _ shortcut: ShortcutBinding? = nil,
                 _ run: @escaping () -> Void) {
            let combo = shortcut.flatMap { ShortcutStore.shared.shortcut(for: $0)?.display }
            list.append(Command(id: id, title: title,
                                subtitle: combo.map { "\(area) · \($0)" } ?? area,
                                symbol: symbol, keywords: "\(keywords) \(area)", run: run))
        }
        func toolsShortcut(_ key: String) -> ShortcutBinding? {
            ToolsFeature.shortcuts.first { $0.key == key }
        }
        func soundShortcut(_ key: String) -> ShortcutBinding? {
            SoundFeature.shortcuts.first { $0.key == key }
        }

        let awakeArea = L("Mantener despierto", "Keep awake")
        let toolsArea = L("Utilidades", "Tools")
        let clipboardArea = L("Portapapeles", "Clipboard")
        let soundArea = L("Sonido", "Sound")

        if keepAwake.isEnabled {
            add("awake.toggle",
                keepAwake.isActive ? L("Dejar que el Mac se duerma", "Let the Mac sleep")
                                   : L("Mantener el Mac despierto", "Keep the Mac awake"),
                awakeArea, "cup.and.saucer.fill",
                "cafe coffee cafeina caffeine dormir sleep", nil) { keepAwake.toggle() }
        }

        if tools.isEnabled {
            add("tools.ocr", L("Copiar texto de la pantalla", "Copy text from the screen"),
                toolsArea, "text.viewfinder",
                "ocr texto reconocer scan", toolsShortcut("tools.ocr")) { tools.captureText() }
            add("tools.color", L("Copiar un color de la pantalla", "Copy a colour from the screen"),
                toolsArea, "eyedropper",
                "color picker hex cuentagotas", toolsShortcut("tools.color")) { tools.pickColor() }
            add("tools.mic",
                tools.microphoneMuted ? L("Activar el micrófono", "Unmute the microphone")
                                      : L("Silenciar el micrófono", "Mute the microphone"),
                toolsArea, "mic.slash.fill",
                "micro microfono microphone mute callar", toolsShortcut("tools.mic")) { tools.toggleMicrophone() }
            add("tools.lock", L("Bloquear el teclado 30 s", "Lock the keyboard for 30 s"),
                toolsArea, "keyboard",
                "teclado limpiar clean", toolsShortcut("tools.lock")) { tools.lockKeyboard() }
            add("tools.desktop",
                tools.desktopIconsHidden ? L("Mostrar los iconos del escritorio", "Show desktop icons")
                                         : L("Ocultar los iconos del escritorio", "Hide desktop icons"),
                toolsArea, "menubar.dock.rectangle",
                "escritorio desktop iconos limpio", nil) { tools.toggleDesktopIcons() }
            // El mismo paso que el atajo: desde aquí bajaba el doble.
            add("tools.dim", L("Bajar el brillo por debajo del mínimo", "Dim below the minimum"),
                toolsArea, "sun.min.fill",
                "brillo brightness oscuro dark noche night", toolsShortcut("tools.dimDown")) { tools.stepDim(0.1) }
            add("tools.undim", L("Volver al brillo normal", "Back to normal brightness"),
                toolsArea, "sun.max.fill",
                "brillo brightness claro", toolsShortcut("tools.dimUp")) { tools.dimLevel = 0 }
        }

        if clipboard.isEnabled {
            add("clipboard.panel", L("Historial del portapapeles", "Clipboard history"),
                clipboardArea, "doc.on.clipboard",
                "portapapeles clipboard pegar paste copiar",
                ClipboardFeature.historyShortcut) { clipboard.togglePanel() }
            add("clipboard.plain", L("Pegar sin formato", "Paste as plain text"),
                clipboardArea, "doc.plaintext",
                "pegar paste plano plain formato",
                ClipboardFeature.plainShortcut) { clipboard.pastePlain() }
            add("clipboard.cleanurl", L("Limpiar el rastreo del enlace copiado", "Strip tracking from the copied link"),
                clipboardArea, "link",
                "url enlace link limpiar rastreo utm tracking", nil) { clipboard.cleanClipboardURL() }
        }

        if sound.isEnabled {
            add("sound.mixer", L("Mezclador de volumen", "Volume mixer"),
                soundArea, "slider.vertical.3",
                "mezclador mixer volumen volume apps", soundShortcut("sound.mixer")) { sound.toggleMixer() }
            add("sound.cycle", L("Cambiar de altavoces", "Switch speakers"),
                soundArea, "hifispeaker.fill",
                "salida output altavoz auriculares audio", soundShortcut("sound.cycleOutput")) { sound.cycleOutput() }
        }

        add("settings", L("Ajustes de OmniMac", "OmniMac settings"),
            L("Ajustes", "Settings"), "gearshape.fill",
            "preferencias preferences opciones modulos", nil) {
            SettingsWindowController.shared.show()
        }
        return list
    }

    /// Las apps instaladas, para poder abrirlas desde aquí.
    ///
    /// Se listan por el nombre que enseña el Finder, no por el del archivo: en un Mac
    /// en español «Ajustes del Sistema» está en disco como `System Settings.app`, y
    /// buscarlo por su nombre no lo encontraba.
    private static func applications() -> [Command] {
        let folders = ["/Applications", "/Applications/Utilities",
                       "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        let manager = FileManager.default
        var seen = Set<String>()
        var result: [Command] = []

        func add(_ path: String) {
            let file = (path as NSString).lastPathComponent
            let shown = manager.displayName(atPath: path)
            let title = shown.isEmpty ? String(file.dropLast(4)) : shown
            guard seen.insert(title).inserted else { return }
            result.append(Command(id: "app:\(path)", title: title,
                                  subtitle: L("Abrir la app", "Open the app"),
                                  symbol: "app.fill",
                                  keywords: "\(String(file.dropLast(4))) abrir open launch app") {
                open(path, named: title)
            })
        }

        // El Finder a mano: vive en CoreServices, y esa carpeta está llena de
        // ayudantes que nadie quiere abrir (PIPAgent, PeopleMessageService…).
        add("/System/Library/CoreServices/Finder.app")

        for folder in folders {
            guard let names = try? manager.contentsOfDirectory(atPath: folder) else { continue }
            for name in names {
                let path = folder + "/" + name
                if name.hasSuffix(".app") {
                    add(path)
                } else if folder == "/Applications", !name.hasPrefix(".") {
                    // Un nivel más adentro: Adobe, Microsoft y compañía meten sus
                    // apps en una carpeta con su nombre.
                    for inner in (try? manager.contentsOfDirectory(atPath: path)) ?? []
                    where inner.hasSuffix(".app") {
                        add(path + "/" + inner)
                    }
                }
            }
        }
        return result
    }

    /// Abre la app y, si no se puede (se ha movido, Gatekeeper la bloquea), lo dice.
    /// Antes se descartaba el resultado y el panel se cerraba como si todo fuera bien.
    private static func open(_ path: String, named title: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                Toast.show(L("No se pudo abrir \(title)", "Couldn't open \(title)"),
                           symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
