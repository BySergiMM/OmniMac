import AppKit

/// Punto de entrada: crea la NSApplication con `AppDelegate` y arranca el bucle de eventos.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
