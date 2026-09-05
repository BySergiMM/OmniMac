import AppKit
import ApplicationServices

// Vuelca por Accesibilidad las ventanas (y menús abiertos) de una app: rol, texto,
// posición y tamaño de cada elemento. Uso: swift scripts/dev/axdump.swift <nombre de app> [filtro]
let a = CommandLine.arguments
guard a.count >= 2, let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == a[1] }) else { print("uso: axdump.swift <app> [filtro]"); exit(1) }
let filter = a.count > 2 ? a[2] : ""
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ n: String) -> Any? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func rect(_ e: AXUIElement) -> String {
    guard let pv = attr(e, "AXPosition"), let sv = attr(e, "AXSize") else { return "" }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return "@\(Int(p.x)),\(Int(p.y)) \(Int(s.width))×\(Int(s.height))"
}
func walk(_ e: AXUIElement, _ depth: Int) {
    guard depth < 25 else { return }
    let role = attr(e, "AXRole") as? String ?? "?"
    let texts = ["AXTitle", "AXDescription", "AXValue", "AXHelp"].compactMap { attr(e, $0) as? String }.filter { !$0.isEmpty }
    let label = texts.joined(separator: " · ")
    if role != "AXGroup" || !label.isEmpty {
        let line = "\(String(repeating: " ", count: depth))\(role) «\(label.prefix(90))» \(rect(e))"
        if filter.isEmpty || line.localizedCaseInsensitiveContains(filter) { print(line) }
    }
    for child in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
}
for w in (attr(ax, "AXWindows") as? [AXUIElement]) ?? [] { print("== ventana \(rect(w))"); walk(w, 1) }
if let bar = attr(ax, "AXExtrasMenuBar") { print("== barra de estado"); walk(bar as! AXUIElement, 1) }
if let bar = attr(ax, "AXMenuBar") { print("== menú"); walk(bar as! AXUIElement, 1) }
