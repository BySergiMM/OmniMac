import AppKit
import SwiftUI

/// Ventana de Ajustes (una sola instancia): la crea la primera vez, la muestra y la trae al frente.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        // Barra de título normal (opaca, unificada con la barra de herramientas), como
        // Ajustes del Sistema: el contenido se desplaza por debajo sin superponerse al
        // título. (Antes era transparente y a pantalla completa y el título pisaba la cabecera.)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "OmniMac"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    /// La vista se crea al mostrar la ventana y se destruye al cerrarla: así las páginas
    /// que muestrean (Rendimiento, volumen por app) paran de verdad al cerrar Ajustes.
    /// (Con la ventana solo oculta, SwiftUI no llama a `onDisappear` y seguían midiendo.)
    private func installFreshContent() {
        window?.contentView = NSHostingView(rootView: SettingsView(manager: FeatureManager.shared))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no está soportado")
    }

    func show() {
        PermissionsMonitor.shared.startWatching()
        NSApp.activate(ignoringOtherApps: true)
        if let window, !window.isVisible {
            installFreshContent()
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        PermissionsMonitor.shared.stopWatching()
        FeatureManager.shared.sound.mixer.endWatching()   // por si se cerró con la página Sonido a la vista
        window?.contentView = nil
    }
}
