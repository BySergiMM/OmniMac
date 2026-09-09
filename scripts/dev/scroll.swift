import AppKit
// Rueda del ratón sintética. Uso: scroll.swift <x> <y> <líneas> [pasos] [pausa]
// líneas negativas = hacia abajo (contenido sube)
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count >= 3 else { print("uso: scroll.swift x y líneas [pasos] [pausa]"); exit(1) }
let p = CGPoint(x: a[0], y: a[1]); let lines = Int32(a[2])
let steps = a.count > 3 ? Int(a[3]) : 1
let pause = a.count > 4 ? a[4] : 0.05
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120_000)
for _ in 0..<steps {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
    e.location = p
    e.post(tap: .cghidEventTap)
    usleep(useconds_t(pause * 1_000_000))
}
