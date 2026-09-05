import AppKit
import ApplicationServices
// Herramienta de pruebas del notch (Accesibilidad). Uso:
//   swift scripts/dev/notch.swift height        → alto del panel del notch (32 = plegado)
//   swift scripts/dev/notch.swift dump          → botones y textos del notch
//   swift scripts/dev/notch.swift press:<texto> → pulsa el primer botón cuyo título/descr./ayuda contenga <texto>
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.seergiii.omnimac").first else { print("OmniMac no corre"); exit(1) }
let mode = CommandLine.arguments.dropFirst().first ?? "height"
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let pv = attr(e, "AXPosition"), let sv = attr(e, "AXSize") else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
let windows = (attr(ax, "AXWindows") as? [AXUIElement]) ?? []
guard let notch = windows.first(where: { (frame($0)?.minY ?? -1) == 0 }) else { print("sin panel"); exit(0) }
if mode == "height" { print(Int(frame(notch)!.height)); exit(0) }
var items: [(String, String, AXUIElement)] = []
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = attr(e, "AXRole") as? String ?? "?"
    let label = [attr(e, "AXTitle"), attr(e, "AXDescription"), attr(e, "AXValue"), attr(e, "AXHelp")].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
    if ["AXButton", "AXStaticText", "AXCheckBox"].contains(role) { items.append((role, label, e)) }
    if depth < 16 { for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth + 1) } }
}
walk(notch, 0)
if mode.hasPrefix("press:") {
    let wanted = String(mode.dropFirst(6))
    if let hit = items.first(where: { $0.0 != "AXStaticText" && $0.1.contains(wanted) }) { AXUIElementPerformAction(hit.2, "AXPress" as CFString); print("→ pulsado «\(hit.1.prefix(50))»") } else { print("→ no encontré «\(wanted)»") }
} else {
    for (role, label, _) in items { print("\(role) «\(label.prefix(80))»") }
}
