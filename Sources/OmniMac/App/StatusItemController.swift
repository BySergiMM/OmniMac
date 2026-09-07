import AppKit
import Combine

/// Icono y menú de OmniMac en la barra de menús.
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Nombre con el que macOS recuerda dónde dejó el usuario este icono. Lo usa
    /// también el módulo de la barra de menús para recolocarlo.
    static let autosaveName = "com.seergiii.omnimac.main"

    private let statusItem: NSStatusItem
    private let manager = FeatureManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var titleTimer: Timer?
    /// Iconos sueltos de los módulos que el usuario haya sacado a la barra.
    private var moduleItems: [String: NSStatusItem] = [:]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        super.init()

        updateIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Iconos por módulo: se crean y se quitan según lo que elija el usuario.
        ModuleIcons.shared.$enabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in self?.refreshModuleItems(ids) }
            .store(in: &cancellables)

        manager.keepAwake.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.updateTitle()
                self?.updateModuleIcons()
            }
            .store(in: &cancellables)
        manager.keepAwake.$deadline
            .combineLatest(manager.keepAwake.$showRemainingInMenuBar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
        // Temporizador del notch: su cuenta atrás va junto al icono mientras exista.
        NotchTimer.shared.$remaining
            .combineLatest(NotchTimer.shared.$running)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    /// Con un menú abierto, el notch deja de seguir el ratón: no va a abrirse porque
    /// pases por encima de un menú, y así el sistema tiene una cosa menos que hacer
    /// justo cuando está ocupado dibujándolo.
    func menuWillOpen(_ menu: NSMenu) {
        manager.notch.setMouseTrackingPaused(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        manager.notch.setMouseTrackingPaused(false)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Los iconos sueltos de cada módulo llevan su propio menú, con lo suyo y nada más.
        if let identifier = menu.identifier?.rawValue, identifier.hasPrefix("module.") {
            buildModuleMenu(menu, id: String(identifier.dropFirst("module.".count)))
            return
        }
        buildMainMenu(menu)
    }

    /// El menú del icono general: todo lo que está activo, por secciones.
    private func buildMainMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if manager.keepAwake.isEnabled {
            buildKeepAwakeSection(menu)
        }
        if NotchTimer.shared.isSet {
            if menu.items.count > 0 { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: L("Temporizador", "Timer")))
            let status = NSMenuItem(title: "⏱ \(NotchTimer.shared.remainingText) · \(NotchTimer.shared.phaseText)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            let stop = NSMenuItem(title: NotchTimer.shared.running ? L("Pausar", "Pause") : L("Continuar", "Resume"), action: #selector(toggleTimer), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            let cancel = NSMenuItem(title: L("Parar el temporizador", "Stop the timer"), action: #selector(stopTimer), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        buildFeatureToggles(menu)

        if manager.clipboard.isEnabled {
            menu.addItem(.separator())
            let clipboardItem = NSMenuItem(title: L("Historial del portapapeles…", "Clipboard history…"),
                                           action: #selector(showClipboard),
                                           keyEquivalent: "")
            clipboardItem.target = self
            menu.addItem(clipboardItem)

            let pauseItem = NSMenuItem(title: L("Pausar el historial del portapapeles", "Pause the clipboard history"),
                                       action: #selector(toggleClipboardPause),
                                       keyEquivalent: "")
            pauseItem.target = self
            pauseItem.state = manager.clipboard.paused ? .on : .off
            menu.addItem(pauseItem)
        }

        if manager.tools.isEnabled {
            buildToolsSection(menu)
        }

        if manager.sound.isEnabled {
            buildSoundSection(menu)
        }

        if manager.snapping.isEnabled {
            buildLayoutsSection(menu)
        }

        if !Permissions.hasAccessibility {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: L("⚠️ Falta el permiso de Accesibilidad…", "⚠️ Accessibility permission missing…"),
                                     action: #selector(grantAccessibility),
                                     keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
        }

        menu.addItem(.separator())

        let coffee = NSMenuItem(title: L("☕️ Invítame a un café…", "☕️ Buy me a coffee…"), action: #selector(openCoffee), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)

        let updates = NSMenuItem(title: L("Buscar actualizaciones…", "Check for updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: L("Ajustes…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: L("Salir de OmniMac", "Quit OmniMac"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Iconos sueltos por módulo

    /// Crea o quita los iconos sueltos según los módulos elegidos.
    private func refreshModuleItems(_ ids: Set<String>) {
        for (id, item) in moduleItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            moduleItems[id] = nil
        }
        for id in ModuleIcons.available where ids.contains(id) && moduleItems[id] == nil {
            guard let feature = manager.all.first(where: { $0.featureID == id }) else { continue }
            // Sitio reservado a la derecha de la flecha del escondedor: los iconos
            // nuevos nacen a la izquierda del todo y ahí se los tragaría.
            let name = "omnimac.module.\(id)"
            let positionKey = "NSStatusItem Preferred Position \(name)"
            if UserDefaults.standard.object(forKey: positionKey) == nil {
                UserDefaults.standard.set(ModuleIcons.position(id), forKey: positionKey)
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = name
            item.button?.image = NSImage(systemSymbolName: feature.symbol, accessibilityDescription: feature.displayName)
            item.button?.toolTip = feature.displayName
            let menu = NSMenu()
            menu.delegate = self
            menu.identifier = NSUserInterfaceItemIdentifier("module.\(id)")
            item.menu = menu
            moduleItems[id] = item
        }
        updateModuleIcons()
    }

    /// Refresca lo que enseñan los iconos sueltos (la taza encendida, por ejemplo).
    private func updateModuleIcons() {
        guard let item = moduleItems["keepawake"] else { return }
        let active = manager.keepAwake.isActive
        item.button?.image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
                                     accessibilityDescription: manager.keepAwake.displayName)
    }

    /// El menú de un icono suelto: las acciones de ese módulo y poco más.
    private func buildModuleMenu(_ menu: NSMenu, id: String) {
        menu.removeAllItems()
        switch id {
        case "keepawake": buildKeepAwakeSection(menu)
        case "clipboard":
            let history = NSMenuItem(title: L("Historial del portapapeles…", "Clipboard history…"),
                                     action: #selector(showClipboard), keyEquivalent: "")
            history.target = self
            menu.addItem(history)
            let pause = NSMenuItem(title: L("Pausar el historial", "Pause the history"),
                                   action: #selector(toggleClipboardPause), keyEquivalent: "")
            pause.target = self
            pause.state = manager.clipboard.paused ? .on : .off
            menu.addItem(pause)
        case "tools": buildToolsSection(menu)
        case "sound": buildSoundSection(menu)
        case "snapping": buildLayoutsSection(menu)
        default: break
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L("Ajustes…", "Settings…"), action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    // MARK: - Secciones

    /// Utilidades: OCR, micrófono, teclado y escritorio.
    private func buildToolsSection(_ menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: L("Utilidades", "Tools")))
        let ocr = NSMenuItem(title: L("Copiar texto de la pantalla…", "Copy text from the screen…"), action: #selector(captureText), keyEquivalent: "")
        ocr.target = self
        menu.addItem(ocr)
        let mic = NSMenuItem(title: L("Silenciar el micrófono", "Mute the microphone"), action: #selector(toggleMicrophone), keyEquivalent: "")
        mic.target = self
        mic.state = manager.tools.microphoneMuted ? .on : .off
        menu.addItem(mic)
        let lock = NSMenuItem(title: L("Bloquear el teclado 30 s (para limpiarlo)", "Lock the keyboard for 30 s (to clean it)"), action: #selector(lockKeyboard), keyEquivalent: "")
        lock.target = self
        menu.addItem(lock)
        let desktop = NSMenuItem(title: L("Ocultar los iconos del escritorio", "Hide desktop icons"), action: #selector(toggleDesktopIcons), keyEquivalent: "")
        desktop.target = self
        desktop.state = manager.tools.desktopIconsHidden ? .on : .off
        menu.addItem(desktop)
    }

    /// Sonido: salida, entrada y silencio.
    private func buildSoundSection(_ menu: NSMenu) {
        manager.sound.refresh()
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: L("Sonido", "Sound")))
        let outputItem = NSMenuItem(title: L("Salida: \(manager.sound.outputName)", "Output: \(manager.sound.outputName)"), action: nil, keyEquivalent: "")
        let outputMenu = NSMenu()
        for device in manager.sound.outputDevices {
            let item = NSMenuItem(title: device.name, action: #selector(selectOutput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: device.id)
            item.state = device.id == manager.sound.output ? .on : .off
            outputMenu.addItem(item)
        }
        outputItem.submenu = outputMenu
        menu.addItem(outputItem)
        let inputItem = NSMenuItem(title: L("Entrada: \(manager.sound.inputName)", "Input: \(manager.sound.inputName)"), action: nil, keyEquivalent: "")
        let inputMenu = NSMenu()
        for device in manager.sound.inputDevices {
            let item = NSMenuItem(title: device.name, action: #selector(selectInput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: device.id)
            item.state = device.id == manager.sound.input ? .on : .off
            inputMenu.addItem(item)
        }
        inputItem.submenu = inputMenu
        menu.addItem(inputItem)
        let muteOutput = NSMenuItem(title: L("Silenciar la salida", "Mute the output"), action: #selector(toggleOutputMute), keyEquivalent: "")
        muteOutput.target = self
        muteOutput.state = manager.sound.outputMuted ? .on : .off
        menu.addItem(muteOutput)
    }

    /// Disposiciones de ventanas guardadas.
    private func buildLayoutsSection(_ menu: NSMenu) {
        menu.addItem(.separator())
        let layoutsItem = NSMenuItem(title: L("Disposiciones de ventanas", "Window layouts"), action: nil, keyEquivalent: "")
        let layoutsMenu = NSMenu()
        for layout in WindowLayoutStore.shared.layouts {
            let shortcut = layout.shortcutLabel.map { "   \($0)" } ?? ""
            let item = NSMenuItem(title: "\(layout.name)\(shortcut)", action: #selector(applyLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout
            layoutsMenu.addItem(item)
        }
        if !WindowLayoutStore.shared.layouts.isEmpty { layoutsMenu.addItem(.separator()) }
        if WindowLayoutStore.shared.canUndo {
            let undo = NSMenuItem(title: L("Deshacer la última disposición   ⌃⌥ 0", "Undo the last layout   ⌃⌥ 0"), action: #selector(undoLayout), keyEquivalent: "")
            undo.target = self
            layoutsMenu.addItem(undo)
        }
        let save = NSMenuItem(title: L("Guardar la disposición actual…", "Save the current layout…"), action: #selector(saveLayoutPrompt), keyEquivalent: "")
        save.target = self
        layoutsMenu.addItem(save)
        layoutsItem.submenu = layoutsMenu
        menu.addItem(layoutsItem)
    }

    private func buildKeepAwakeSection(_ menu: NSMenu) {
        let keepAwake = manager.keepAwake
        menu.addItem(NSMenuItem.sectionHeader(title: L("Mantener despierto", "Keep awake")))

        if keepAwake.isActive {
            let statusTitle: String
            if let remaining = keepAwake.remainingDescription {
                statusTitle = L("Activo · queda \(remaining)", "Active · \(remaining) left")
            } else {
                statusTitle = L("Activo · sin límite", "Active · no limit")
            }
            let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            status.isEnabled = false
            status.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            menu.addItem(status)

            let off = NSMenuItem(title: L("Desactivar", "Turn off"), action: #selector(keepAwakeOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        } else {
            let options: [(String, Int?)] = [
                (L("Activar sin límite", "Keep awake indefinitely"), nil),
                (L("Activar 15 minutos", "Keep awake for 15 minutes"), 15),
                (L("Activar 30 minutos", "Keep awake for 30 minutes"), 30),
                (L("Activar 1 hora", "Keep awake for 1 hour"), 60),
                (L("Activar 2 horas", "Keep awake for 2 hours"), 120),
                (L("Activar 4 horas", "Keep awake for 4 hours"), 240),
                (L("Activar 8 horas", "Keep awake for 8 hours"), 480),
            ]
            for (title, minutes) in options {
                let item = NSMenuItem(title: title, action: #selector(keepAwakeOn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                menu.addItem(item)
            }

            // Hasta una hora concreta: las próximas 12 horas en punto.
            let until = NSMenuItem(title: L("Activar hasta las…", "Keep awake until…"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            var next = Calendar.current.nextDate(after: Date(),
                                                 matching: DateComponents(minute: 0),
                                                 matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
            for _ in 0..<12 {
                let item = NSMenuItem(title: formatter.string(from: next), action: #selector(keepAwakeUntil(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = next
                submenu.addItem(item)
                next = next.addingTimeInterval(3600)
            }
            until.submenu = submenu
            menu.addItem(until)
        }
    }

    private func buildFeatureToggles(_ menu: NSMenu) {
        menu.addItem(NSMenuItem.sectionHeader(title: L("Módulos", "Modules")))
        for feature in manager.all {
            let item = NSMenuItem(title: feature.displayName,
                                  action: #selector(toggleFeature(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = feature
            item.state = feature.isEnabled ? .on : .off
            menu.addItem(item)
        }
    }

    // MARK: - Acciones

    @objc private func keepAwakeOn(_ sender: NSMenuItem) {
        manager.keepAwake.activate(minutes: sender.representedObject as? Int)
    }

    @objc private func keepAwakeUntil(_ sender: NSMenuItem) {
        guard let date = sender.representedObject as? Date else { return }
        manager.keepAwake.activate(until: date)
    }

    @objc private func keepAwakeOff() {
        manager.keepAwake.deactivate()
    }

    @objc private func checkForUpdates() {
        UpdaterController.shared.checkForUpdates()
    }

    @objc private func toggleTimer() {
        let timer = NotchTimer.shared
        if timer.running { timer.pause() } else { timer.resume() }
    }

    @objc private func stopTimer() {
        NotchTimer.shared.stop()
    }

    @objc private func undoLayout() {
        WindowLayoutStore.shared.undoLast()
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? WindowLayout else { return }
        WindowLayoutStore.shared.apply(layout)
    }

    /// Pide un nombre y guarda dónde están las ventanas ahora mismo.
    @objc private func saveLayoutPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Guardar la disposición actual", "Save the current layout")
        alert.informativeText = L("Ponle un nombre. Después podrás volver a colocar todas las ventanas así desde este menú, desde Ajustes o con ⌃⌥ + número.", "Give it a name. Afterwards you can put every window back like this from this menu, from Settings or with ⌃⌥ + number.")
        alert.addButton(withTitle: L("Guardar", "Save"))
        alert.addButton(withTitle: L("Cancelar", "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = L("Trabajo, Monitor, Presentación…", "Work, Monitor, Presentation…")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            WindowLayoutStore.shared.saveCurrent(named: field.stringValue)
        }
    }

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        guard let feature = sender.representedObject as? BaseFeature else { return }
        feature.isEnabled.toggle()
    }

    @objc private func showClipboard() {
        manager.clipboard.togglePanel()
    }

    @objc private func toggleClipboardPause() {
        manager.clipboard.paused.toggle()
    }

    @objc private func captureText() {
        manager.tools.captureText()
    }

    @objc private func toggleMicrophone() {
        manager.tools.toggleMicrophone()
    }

    @objc private func lockKeyboard() {
        manager.tools.lockKeyboard()
    }

    @objc private func toggleDesktopIcons() {
        manager.tools.toggleDesktopIcons()
    }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        manager.sound.selectOutput(id)
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        manager.sound.selectInput(id)
    }

    @objc private func toggleOutputMute() {
        manager.sound.outputMuted.toggle()
    }

    @objc private func grantAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func openCoffee() {
        NSWorkspace.shared.open(Brand.coffeeURL)
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateIcon() {
        // Los destellos del icono de la app, no unos deslizadores: «switch.2» era
        // casi igual que el icono del Centro de Control y se confundían en la barra.
        let symbol = manager.keepAwake.isActive ? "cup.and.saucer.fill" : "sparkles"
        let description = manager.keepAwake.isActive ? L("OmniMac (mantener despierto activo)", "OmniMac (keep awake on)") : "OmniMac"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        statusItem.button?.imagePosition = .imageLeading
    }

    /// Tiempo restante junto al icono mientras hay una sesión con temporizador.
    /// Se refresca cada 30 s (con tolerancia) solo mientras hace falta.
    private func updateTitle() {
        if NotchTimer.shared.isSet {
            statusItem.button?.title = " " + NotchTimer.shared.remainingText + (NotchTimer.shared.running ? "" : " ⏸")
            return
        }
        titleTimer?.invalidate()
        titleTimer = nil
        let keepAwake = manager.keepAwake
        guard keepAwake.isActive, keepAwake.showRemainingInMenuBar,
              let remaining = keepAwake.remainingDescription else {
            statusItem.button?.title = ""
            return
        }
        statusItem.button?.title = " " + remaining
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
        timer.tolerance = 10
        titleTimer = timer
    }
}
