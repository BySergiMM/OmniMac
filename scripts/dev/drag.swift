import AppKit

// Arrastre sintético con el ratón por varios puntos (para la bandeja/AirDrop del notch y
// el ajuste de ventanas a los bordes). Uso:
//   swift scripts/dev/drag.swift x1 y1 x2 y2 [x3 y3 ...]
// Variables opcionales: DRAG_SECONDS (por tramo, 1.2) y DRAG_HOLD (pausa en cada punto, 0.8).
// Coordenadas en puntos de pantalla, origen arriba a la izquierda.
let nums = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard nums.count >= 4, nums.count % 2 == 0 else { print("uso: drag.swift x1 y1 x2 y2 [x3 y3 …]"); exit(1) }
let points = stride(from: 0, to: nums.count, by: 2).map { CGPoint(x: nums[$0], y: nums[$0 + 1]) }
let seconds = Double(ProcessInfo.processInfo.environment["DRAG_SECONDS"] ?? "") ?? 1.2
let hold = Double(ProcessInfo.processInfo.environment["DRAG_HOLD"] ?? "") ?? 0.8
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
post(.mouseMoved, points[0]); usleep(150_000)
post(.leftMouseDown, points[0]); usleep(250_000)
for (from, to) in zip(points, points.dropFirst()) {
    let steps = 60
    for i in 1...steps {
        let t = Double(i) / Double(steps), e = (1 - cos(t * .pi)) / 2
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e))
        usleep(useconds_t(seconds * 1_000_000 / Double(steps)))
    }
    Thread.sleep(forTimeInterval: hold)
}
post(.leftMouseUp, points.last!)
print("arrastre por \(points.count) puntos")
