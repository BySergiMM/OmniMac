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
        CacheCleaner.shared.startAutomaticCleaning()
        // Gráficas de rendimiento: notch, barra de menús o en ningún sitio.
        MenuBarStats.apply()   // limpieza de caché diaria (si está activada)
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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        FeatureManager.shared.keepAwake.deactivate()
    }
}
