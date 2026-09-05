import AppKit
// Herramienta de pruebas: mueve el ratón. Uso: swift scripts/dev/mouse.swift hover|park
// hover → al notch (borde superior, centro), con un pequeño movimiento para generar eventos
// park  → lejos del notch (centro de la pantalla)
guard let screen = NSScreen.main else { exit(1) }
let midX = screen.frame.midX
func move(_ x: CGFloat, _ y: CGFloat) {
    let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    e?.post(tap: .cghidEventTap); usleep(40_000)
}
if CommandLine.arguments.dropFirst().first == "park" {
    move(midX, screen.frame.height / 2)
} else {
    move(midX - 30, 12); move(midX - 10, 6); move(midX, 2); move(midX + 4, 1)
}
