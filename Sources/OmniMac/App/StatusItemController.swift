import AppKit
import Combine

/// Icono y menú de OmniMac en la barra de menús.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager = FeatureManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var titleTimer: Timer?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        updateIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        manager.keepAwake.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.updateTitle()
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if manager.keepAwake.isEnabled {
            buildKeepAwakeSection(menu)
        }
        if NotchTimer.shared.isSet {
            if menu.items.count > 0 { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: "Temporizador"))
            let status = NSMenuItem(title: "⏱ \(NotchTimer.shared.remainingText) · \(NotchTimer.shared.phaseText)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            let stop = NSMenuItem(title: NotchTimer.shared.running ? "Pausar" : "Continuar", action: #selector(toggleTimer), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            let cancel = NSMenuItem(title: "Parar el temporizador", action: #selector(stopTimer), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        buildFeatureToggles(menu)

        if manager.clipboard.isEnabled {
            menu.addItem(.separator())
            let clipboardItem = NSMenuItem(title: "Historial del portapapeles…",
                                           action: #selector(showClipboard),
                                           keyEquivalent: "")
            clipboardItem.target = self
            menu.addItem(clipboardItem)

            let pauseItem = NSMenuItem(title: "Pausar el historial del portapapeles",
                                       action: #selector(toggleClipboardPause),
                                       keyEquivalent: "")
            pauseItem.target = self
            pauseItem.state = manager.clipboard.paused ? .on : .off
            menu.addItem(pauseItem)
        }

        if manager.tools.isEnabled {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: "Utilidades"))
            let ocr = NSMenuItem(title: "Copiar texto de la pantalla…", action: #selector(captureText), keyEquivalent: "")
            ocr.target = self
            menu.addItem(ocr)
            let mic = NSMenuItem(title: "Silenciar el micrófono", action: #selector(toggleMicrophone), keyEquivalent: "")
            mic.target = self
            mic.state = manager.tools.microphoneMuted ? .on : .off
            menu.addItem(mic)
            let lock = NSMenuItem(title: "Bloquear el teclado 30 s (para limpiarlo)", action: #selector(lockKeyboard), keyEquivalent: "")
            lock.target = self
            menu.addItem(lock)
            let desktop = NSMenuItem(title: "Ocultar los iconos del escritorio", action: #selector(toggleDesktopIcons), keyEquivalent: "")
            desktop.target = self
            desktop.state = manager.tools.desktopIconsHidden ? .on : .off
            menu.addItem(desktop)
        }

        if manager.sound.isEnabled {
            manager.sound.refresh()
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: "Sonido"))
            let outputItem = NSMenuItem(title: "Salida: \(manager.sound.outputName)", action: nil, keyEquivalent: "")
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
            let inputItem = NSMenuItem(title: "Entrada: \(manager.sound.inputName)", action: nil, keyEquivalent: "")
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
            let muteOutput = NSMenuItem(title: "Silenciar la salida", action: #selector(toggleOutputMute), keyEquivalent: "")
            muteOutput.target = self
            muteOutput.state = manager.sound.outputMuted ? .on : .off
            menu.addItem(muteOutput)
        }

        if manager.snapping.isEnabled {
            menu.addItem(.separator())
            let layoutsItem = NSMenuItem(title: "Disposiciones de ventanas", action: nil, keyEquivalent: "")
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
                let undo = NSMenuItem(title: "Deshacer la última disposición   ⌃⌥ 0", action: #selector(undoLayout), keyEquivalent: "")
                undo.target = self
                layoutsMenu.addItem(undo)
            }
            let save = NSMenuItem(title: "Guardar la disposición actual…", action: #selector(saveLayoutPrompt), keyEquivalent: "")
            save.target = self
            layoutsMenu.addItem(save)
            layoutsItem.submenu = layoutsMenu
            menu.addItem(layoutsItem)
        }

        if !Permissions.hasAccessibility {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: "⚠️ Falta el permiso de Accesibilidad…",
                                     action: #selector(grantAccessibility),
                                     keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
        }

        menu.addItem(.separator())

        let coffee = NSMenuItem(title: "☕️ Invítame a un café…", action: #selector(openCoffee), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)

        let updates = NSMenuItem(title: "Buscar actualizaciones…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Salir de OmniMac", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Secciones

    private func buildKeepAwakeSection(_ menu: NSMenu) {
        let keepAwake = manager.keepAwake
        menu.addItem(NSMenuItem.sectionHeader(title: "Mantener despierto"))

        if keepAwake.isActive {
            let statusTitle: String
            if let remaining = keepAwake.remainingDescription {
                statusTitle = "Activo · queda \(remaining)"
            } else {
                statusTitle = "Activo · sin límite"
            }
            let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            status.isEnabled = false
            status.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            menu.addItem(status)

            let off = NSMenuItem(title: "Desactivar", action: #selector(keepAwakeOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        } else {
            let options: [(String, Int?)] = [
                ("Activar sin límite", nil),
                ("Activar 15 minutos", 15),
                ("Activar 30 minutos", 30),
                ("Activar 1 hora", 60),
                ("Activar 2 horas", 120),
                ("Activar 4 horas", 240),
                ("Activar 8 horas", 480),
            ]
            for (title, minutes) in options {
                let item = NSMenuItem(title: title, action: #selector(keepAwakeOn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                menu.addItem(item)
            }

            // Hasta una hora concreta: las próximas 12 horas en punto.
            let until = NSMenuItem(title: "Activar hasta las…", action: nil, keyEquivalent: "")
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
        menu.addItem(NSMenuItem.sectionHeader(title: "Módulos"))
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
        alert.messageText = "Guardar la disposición actual"
        alert.informativeText = "Ponle un nombre. Después podrás volver a colocar todas las ventanas así desde este menú, desde Ajustes o con ⌃⌥ + número."
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Trabajo, Monitor, Presentación…"
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
        let symbol = manager.keepAwake.isActive ? "cup.and.saucer.fill" : "switch.2"
        let description = manager.keepAwake.isActive ? "OmniMac (mantener despierto activo)" : "OmniMac"
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
