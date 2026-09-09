import AppKit
// Mueve el puntero sin pulsar nada. Uso: point.swift <x> <y>
// Hace falta para grabar: al aparcar el ratón con un clic se dispara lo que haya debajo.
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count == 2 else { print("uso: point.swift x y"); exit(1) }
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: CGPoint(x: a[0], y: a[1]), mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(80_000)
