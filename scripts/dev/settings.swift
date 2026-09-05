import AppKit
import ApplicationServices
// Herramienta de pruebas de la ventana de Ajustes (Accesibilidad). Uso:
//   swift scripts/dev/settings.swift dump            → controles y textos con sus marcos
//   swift scripts/dev/settings.swift press:<texto>   → pulsa el primer botón/casilla/desplegable/menú que contenga <texto>
//   swift scripts/dev/settings.swift near:<texto>    → pulsa la casilla en la misma línea que el texto
//   swift scripts/dev/settings.swift click:<texto>   → clic real (ratón) sobre el texto (para las filas de la barra lateral)
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.seergiii.omnimac").first else { print("OmniMac no corre"); exit(1) }
let mode = CommandLine.arguments.dropFirst().first ?? "dump"
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, "AXPosition"), let sv = attr(e, "AXSize") else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
struct Item { let role: String; let label: String; let frame: CGRect; let element: AXUIElement }
var items: [Item] = []
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = attr(e, "AXRole") as? String ?? "?"
    let value = attr(e, "AXValue"); let valueText = (value as? String) ?? (value.map { "\($0)" } ?? "")
    let label = [(attr(e, "AXTitle") as? String) ?? "", (attr(e, "AXDescription") as? String) ?? "", valueText, (attr(e, "AXHelp") as? String) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    if let f = frame(e), ["AXButton", "AXCheckBox", "AXStaticText", "AXRow", "AXPopUpButton", "AXMenuItem", "AXSlider", "AXRadioButton"].contains(role) { items.append(Item(role: role, label: label, frame: f, element: e)) }
    if depth < 18 { for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth + 1) } }
}
for w in (attr(ax, "AXWindows") as? [AXUIElement]) ?? [] where (frame(w)?.minY ?? 0) > 0 {   // ventanas normales (no el notch)
    if let f = frame(w) { print("VENTANA «\((attr(w, "AXTitle") as? String) ?? "")» x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))") }
    walk(w, 0)
}
let pressable = ["AXButton", "AXCheckBox", "AXRow", "AXRadioButton", "AXPopUpButton", "AXMenuItem"]
if mode == "dump" { for it in items { print("\(it.role) «\(it.label.prefix(70))» x=\(Int(it.frame.minX)) y=\(Int(it.frame.minY)) w=\(Int(it.frame.width)) h=\(Int(it.frame.height))") } }
else if mode.hasPrefix("press:") {
    let w = String(mode.dropFirst(6))
    if let t = items.first(where: { pressable.contains($0.role) && $0.label.contains(w) }) { AXUIElementPerformAction(t.element, "AXPress" as CFString); print("→ pulsado \(t.role) «\(t.label.prefix(50))»") } else { print("→ no encontré «\(w)»") }
} else if mode.hasPrefix("near:") {
    let w = String(mode.dropFirst(5)); var done = false
    for text in items where text.role == "AXStaticText" && text.label.contains(w) {
        if let box = items.first(where: { $0.role == "AXCheckBox" && abs($0.frame.midY - text.frame.midY) < 14 && $0.frame.minX > text.frame.minX }) { AXUIElementPerformAction(box.element, "AXPress" as CFString); print("→ pulsada la casilla junto a «\(w)»"); done = true; break }
    }
    if !done { print("→ no encontré casilla junto a «\(w)»") }
} else if mode.hasPrefix("click:") {
    let w = String(mode.dropFirst(6))
    guard let t = items.first(where: { $0.role == "AXStaticText" && $0.label.contains(w) }) else { print("→ no encontré «\(w)»"); exit(0) }
    let p = CGPoint(x: t.frame.midX, y: t.frame.midY)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(60_000) }
    print("→ clic en «\(w)» (\(Int(p.x)), \(Int(p.y)))")
}
