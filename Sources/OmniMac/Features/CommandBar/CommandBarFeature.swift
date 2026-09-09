import AppKit
import Carbon.HIToolbox

/// Un comando del buscador.
struct Command: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    /// Palabras extra por las que también se encuentra («micro» para el micrófono).
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
/// El índice de apps se construye **una sola vez, al abrir el panel**, y se tira al
/// cerrarlo: recorrer las carpetas de aplicaciones cuesta, y no hay ninguna razón
/// para tenerlo en memoria mientras nadie busca.
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
            // Se ejecuta después de cerrar para que la app que estaba delante
            // recupere el foco antes: si no, cosas como pegar irían al panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { command.run() }
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
        if panel.isVisible { panel.hide() } else { panel.show(commands: buildCommands()) }
    }

    // MARK: - El índice

    private func buildCommands() -> [Command] {
        omniMacCommands() + Self.applications()
    }

    /// Todo lo que sabe hacer OmniMac, en una lista.
    private func omniMacCommands() -> [Command] {
        // Copias locales para que las clausuras no capturen `self`: el buscador
        // puede desaparecer entre que se abre el panel y se pulsa Intro.
        let keepAwake = self.keepAwake, tools = self.tools
        let clipboard = self.clipboard, sound = self.sound
        var list: [Command] = []
        func add(_ id: String, _ title: String, _ subtitle: String, _ symbol: String,
                 _ keywords: String = "", _ run: @escaping () -> Void) {
            list.append(Command(id: id, title: title, subtitle: subtitle, symbol: symbol,
                                keywords: keywords, run: run))
        }

        add("awake.toggle",
            keepAwake.isActive ? L("Dejar que el Mac se duerma", "Let the Mac sleep")
                               : L("Mantener el Mac despierto", "Keep the Mac awake"),
            L("Mantener despierto", "Keep awake"), "cup.and.saucer.fill",
            "cafe coffee cafeina caffeine dormir sleep") { keepAwake.toggle() }

        add("tools.ocr", L("Copiar texto de la pantalla", "Copy text from the screen"),
            L("Utilidades · ⇧⌘2", "Tools · ⇧⌘2"), "text.viewfinder",
            "ocr texto reconocer scan") { tools.captureText() }
        add("tools.color", L("Copiar un color de la pantalla", "Copy a colour from the screen"),
            L("Utilidades · ⇧⌘6", "Tools · ⇧⌘6"), "eyedropper",
            "color picker hex cuentagotas") { tools.pickColor() }
        add("tools.mic",
            tools.microphoneMuted ? L("Activar el micrófono", "Unmute the microphone")
                                  : L("Silenciar el micrófono", "Mute the microphone"),
            L("Utilidades · ⌃⌥⌘M", "Tools · ⌃⌥⌘M"), "mic.slash.fill",
            "micro microfono microphone mute callar") { tools.toggleMicrophone() }
        add("tools.lock", L("Bloquear el teclado 30 s", "Lock the keyboard for 30 s"),
            L("Utilidades · para limpiarlo", "Tools · to clean it"), "keyboard",
            "teclado limpiar clean") { tools.lockKeyboard() }
        add("tools.desktop",
            tools.desktopIconsHidden ? L("Mostrar los iconos del escritorio", "Show desktop icons")
                                     : L("Ocultar los iconos del escritorio", "Hide desktop icons"),
            L("Utilidades", "Tools"), "menubar.dock.rectangle",
            "escritorio desktop iconos limpio") { tools.toggleDesktopIcons() }
        add("tools.dim", L("Bajar el brillo por debajo del mínimo", "Dim below the minimum"),
            L("Utilidades · ⌃⌥⌘−", "Tools · ⌃⌥⌘−"), "sun.min.fill",
            "brillo brightness oscuro dark noche night") { tools.stepDim(0.2) }
        add("tools.undim", L("Volver al brillo normal", "Back to normal brightness"),
            L("Utilidades · ⌃⌥⌘+", "Tools · ⌃⌥⌘+"), "sun.max.fill",
            "brillo brightness claro") { tools.dimLevel = 0 }

        add("clipboard.panel", L("Historial del portapapeles", "Clipboard history"),
            L("⇧⌘V", "⇧⌘V"), "doc.on.clipboard",
            "portapapeles clipboard pegar paste copiar") { clipboard.togglePanel() }
        add("clipboard.plain", L("Pegar sin formato", "Paste as plain text"),
            L("⌥⇧⌘V", "⌥⇧⌘V"), "doc.plaintext",
            "pegar paste plano plain formato") { clipboard.pastePlain() }

        add("clipboard.cleanurl", L("Limpiar el rastreo del enlace copiado", "Strip tracking from the copied link"),
            L("Portapapeles", "Clipboard"), "link",
            "url enlace link limpiar rastreo utm tracking") { clipboard.cleanClipboardURL() }

        add("sound.mixer", L("Mezclador de volumen", "Volume mixer"),
            L("Sonido · ⌃⌥⌘V", "Sound · ⌃⌥⌘V"), "slider.vertical.3",
            "mezclador mixer volumen volume apps") { sound.toggleMixer() }

        add("sound.cycle", L("Cambiar de altavoces", "Switch speakers"),
            L("Sonido · ⌃⌥⌘O", "Sound · ⌃⌥⌘O"), "hifispeaker.fill",
            "salida output altavoz auriculares audio") { sound.cycleOutput() }

        add("settings", L("Ajustes de OmniMac", "OmniMac settings"),
            L("Abrir la ventana de ajustes", "Open the settings window"), "gearshape.fill",
            "preferencias preferences opciones") {
            SettingsWindowController.shared.show()
        }
        return list
    }

    /// Las apps instaladas, para poder abrirlas desde aquí.
    private static func applications() -> [Command] {
        let folders = ["/Applications", "/Applications/Utilities",
                       "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var result: [Command] = []
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let title = String(name.dropLast(4))
                guard seen.insert(title).inserted else { continue }
                let path = folder + "/" + name
                result.append(Command(id: "app:\(path)", title: title,
                                      subtitle: L("Abrir la app", "Open the app"),
                                      symbol: "app.fill", keywords: "abrir open launch app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                })
            }
        }
        return result
    }
}
