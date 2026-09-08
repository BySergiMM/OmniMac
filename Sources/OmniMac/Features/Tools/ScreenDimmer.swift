import AppKit

/// Baja el brillo **por debajo del mínimo de macOS**.
///
/// De noche, o con la pantalla a oscuras, el brillo más bajo que deja el sistema
/// sigue siendo demasiado. Esto pone un velo negro por encima de todo, en todas las
/// pantallas, que deja pasar los clics y no aparece en las capturas del sistema.
///
/// **Por qué solo hacia abajo.** Subir el brillo *por encima* del máximo de macOS no
/// se puede sin trucos: en los Mac con pantalla XDR se hace abriendo una capa HDR
/// para engañar al gestor de brillo, y en los demás sencillamente no hay margen —el
/// máximo es el máximo del panel—. Además de necesitar APIs privadas, mantener la
/// pantalla por encima de su tope de forma sostenida **calienta el equipo y gasta
/// bastante más batería**, que es justo la razón por la que Apple lo limita. Bajar,
/// en cambio, no tiene ningún inconveniente: no toca el hardware, solo dibuja encima.
final class ScreenDimmer {
    /// Cuánto se oscurece, de 0 (nada) a 0,8. Por encima de 0,8 la pantalla queda
    /// prácticamente ilegible y solo sirve para asustarse.
    static let maxLevel = 0.8

    private var windows: [NSWindow] = []
    private var observer: Any?
    private(set) var level: Double = 0

    /// Aplica un nivel. Con 0 se quitan las ventanas del todo: nada de dejar una
    /// ventana transparente por ahí consumiendo composición.
    func apply(_ value: Double) {
        level = min(Self.maxLevel, max(0, value))
        guard level > 0.001 else { return teardown() }
        if windows.isEmpty { build() }
        for window in windows { window.alphaValue = level }
    }

    private func build() {
        // Si cambia la disposición de pantallas (se conecta un monitor), se rehacen.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.level > 0.001 else { return }
                self.teardown(keepingLevel: true)
                self.build()
                for window in self.windows { window.alphaValue = self.level }
            }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            // Por encima de todo, incluso del notch, pero por debajo del salvapantallas.
            window.level = .screenSaver
            // Los clics pasan de largo: es un velo, no una ventana con la que se
            // interactúe.
            window.ignoresMouseEvents = true
            // Que siga ahí al cambiar de escritorio y no salga en las capturas ni en
            // el selector de ventanas.
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.sharingType = .none
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func teardown(keepingLevel: Bool = false) {
        if let observer, !keepingLevel {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if !keepingLevel { level = 0 }
    }

    deinit { teardown() }
}
