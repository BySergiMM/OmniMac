import AppKit

/// Arranque de la app: icono de la barra, módulos, permisos, actualizaciones y ventana de Ajustes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController()
        // `OmniMac --snapshots <carpeta>`: renderiza el notch y el menú a PNG (para la web) y sale.
        if let controller = statusItemController, Snapshots.runIfRequested(menuSource: controller) { return }
        _ = UpdaterController.shared   // comprobación de actualizaciones programada
        CacheCleaner.shared.startAutomaticCleaning()   // limpieza de caché diaria (si está activada)
        startHeartbeatIfAsked()
        // Gráficas de rendimiento: notch, barra de menús o en ningún sitio.
        MenuBarStats.apply()
        FeatureManager.shared.startEnabled()

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

    /// Vigilante del hilo principal, para cuando alguien dice que la app «va lenta».
    ///
    /// Se enciende con `OMNIMAC_HEARTBEAT=1` al arrancar la app desde el Terminal y
    /// anota en el registro del sistema cada vez que el hilo principal se queda
    /// parado más de 180 ms, que es cuando se empieza a notar. Apagado no cuesta nada
    /// porque ni siquiera crea el temporizador.
    ///
    ///     OMNIMAC_HEARTBEAT=1 /Applications/OmniMac.app/Contents/MacOS/OmniMac
    ///
    /// Y para leerlo: `log stream --predicate 'process == "OmniMac"'`
    private func startHeartbeatIfAsked() {
        guard ProcessInfo.processInfo.environment["OMNIMAC_HEARTBEAT"] != nil else { return }
        var last = CFAbsoluteTimeGetCurrent()
        let beat = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            let gap = (now - last) * 1000
            if gap > 180 { NSLog("OmniMac: hilo principal parado %.0f ms", gap) }
            last = now
        }
        RunLoop.main.add(beat, forMode: .common)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        FeatureManager.shared.keepAwake.deactivate()
    }
}
