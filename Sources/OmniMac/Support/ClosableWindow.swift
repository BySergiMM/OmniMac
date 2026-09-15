import AppKit

/// Qué combinación cierra una ventana. Aparte de `NSWindow` para poder probarlo sin
/// abrir ninguna.
enum WindowKeyEquivalent {

    /// ¿Es este un ⌘W de cerrar? Solo el limpio: ⌥⌘W es «cerrar todas las ventanas»
    /// (que aquí no existe) y ⌃W o ⇧⌘W son atajos de otra cosa, así que no se tragan.
    /// Caps Lock, fn y el teclado numérico no pintan nada y se ignoran.
    static func isClose(modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        let used: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        guard modifiers.intersection(used) == .command else { return false }
        return characters?.lowercased() == "w"
    }

    /// La tecla se mira sin modificadores, que es como AppKit resuelve los atajos:
    /// así ⌘W es la tecla marcada «W» en cualquier distribución de teclado.
    static func isClose(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && isClose(modifiers: event.modifierFlags, characters: event.charactersIgnoringModifiers)
    }
}

/// Ventana que se cierra con ⌘W.
///
/// OmniMac vive en la barra de menús con política `.accessory` y nunca construye
/// `NSApp.mainMenu`: sin un menú Archivo no hay ningún «Cerrar ⌘W» que mande
/// `performClose:`, y el atajo no hacía nada. Montar un menú principal solo para eso
/// es tocar algo global en una app que no enseña barra de menús; cerrarse es cosa de
/// la ventana, así que lo resuelve ella y ni ⌘Q ni los atajos del menú de la barra se
/// enteran.
///
/// Cierra por `performClose:` a propósito, no por `close()`: así pasa por el delegado
/// (`windowShouldClose`, `windowWillClose`) igual que el botón rojo, y las páginas que
/// muestrean dejan de medir al cerrar.
final class ClosableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Primero el contenido: si algo de dentro ya usa la combinación, manda él.
        if super.performKeyEquivalent(with: event) { return true }
        guard WindowKeyEquivalent.isClose(event) else { return false }
        performClose(nil)
        return true
    }
}
