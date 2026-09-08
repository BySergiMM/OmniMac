import AppKit

/// Arranque de la app: icono de la barra, módulos, permisos, actualizaciones y ventana de Ajustes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Antes de crear ningún icono: que el escondedor de la barra no acabe
        // tragándose los de OmniMac (AppKit lee la posición al crear cada uno).
        MenuBarFeature.ensureOwnIconsVisible()
        statusItemController = StatusItemController()
        // `OmniMac --snapshots <carpeta>`: renderiza el notch y el menú a PNG (para la web) y sale.
        if let controller = statusItemController, Snapshots.runIfRequested(menuSource: controller) { return }
        _ = UpdaterController.shared   // comprobación de actualizaciones programada
        // Fuera App Nap: macOS frena a las apps sin ventanas y aquí se nota al abrir
        // los menús de la barra, que los dibuja este mismo proceso.
        UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": true])
        CacheCleaner.shared.startAutomaticCleaning()   // limpieza de caché diaria (si está activada)
        startHeartbeatIfAsked()
        // Gráficas de rendimiento: notch, barra de menús o en ningún sitio.
        MenuBarStats.apply()
        FeatureManager.shared.startEnabled()
        // Los avisos son lo único del monitor que corre sin que nadie mire: una
        // muestra barata cada 30 s.
        AlertsMonitor.shared.start()
        DiskImageInstaller.shared.startIfEnabled()
        showWhatsNewIfUpdated()

        // Si algún módulo activado necesita Accesibilidad y no la tenemos, la pedimos:
        // así OmniMac aparece en la lista de Ajustes del Sistema. (Recompilar invalida
        // el permiso porque cambia la firma; al re-marcarlo todo vuelve a funcionar solo.)
        let needsAccessibility = FeatureManager.shared.all.contains { $0.isEnabled && $0.needsAccessibility }
        if needsAccessibility && !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
        }

        // Primera vez: abrimos Ajustes para que el usuario vea qué hay. También tras un
        // reinicio por cambio de idioma, para que siga donde estaba, ya en el idioma nuevo.
        let defaults = UserDefaults.standard
        let reopenAfterLanguageChange = defaults.bool(forKey: Localization.reopenSettingsKey)
        if reopenAfterLanguageChange { defaults.removeObject(forKey: Localization.reopenSettingsKey) }
        if !defaults.bool(forKey: "didFinishOnboarding") || reopenAfterLanguageChange {
            defaults.set(true, forKey: "didFinishOnboarding")
            SettingsWindowController.shared.show()
        }
    }

    // Si el usuario vuelve a abrir la app desde el Finder/Launchpad, mostramos Ajustes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    /// Tras actualizar, enseña una vez lo que trae la versión nueva.
    ///
    /// En una instalación recién hecha no sale nada: ahí lo que se abre es Ajustes con
    /// la bienvenida, y dos ventanas seguidas sobran. La versión vista se guarda
    /// siempre, también la primera vez, para que la próxima actualización sí la note.
    private func showWhatsNewIfUpdated() {
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: ReleaseNotes.lastVersionKey)
        let current = Brand.version
        defer { defaults.set(current, forKey: ReleaseNotes.lastVersionKey) }
        guard ReleaseNotes.shouldShow(current: current, lastSeen: lastSeen) else { return }
        // Un respiro para que la app termine de arrancar y la ventana no pelee con
        // los permisos ni con Ajustes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            WhatsNewWindowController.shared.showCurrent()
        }
    }

    /// Vigilante del hilo principal, para cuando alguien dice que la app «va lenta».
    ///
    /// Se enciende con `OMNIMAC_HEARTBEAT=1` al arrancar la app desde el Terminal y
    /// anota en el registro del sistema cada vez que el hilo principal se queda
    /// parado más de 60 ms, que es cuando se pierde un fotograma y se empieza a
    /// notar el tirón. Apagado no cuesta nada
    /// porque ni siquiera crea el temporizador.
    ///
    ///     OMNIMAC_HEARTBEAT=1 /Applications/OmniMac.app/Contents/MacOS/OmniMac
    ///
    /// Y para leerlo: `log stream --predicate 'process == "OmniMac"'`
    private func startHeartbeatIfAsked() {
        guard ProcessInfo.processInfo.environment["OMNIMAC_HEARTBEAT"] != nil else { return }
        var last = CFAbsoluteTimeGetCurrent()
        let beat = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            let gap = (now - last) * 1000
            if gap > 60 { NSLog("OmniMac: hilo principal parado %.0f ms", gap) }
            last = now
        }
        RunLoop.main.add(beat, forMode: .common)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        FeatureManager.shared.keepAwake.deactivate()
    }
}
