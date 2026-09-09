import AppKit
import ApplicationServices
// Pulsa una opción del menú de OmniMac ya abierto. Uso: menuitem.swift <texto>
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.seergiii.omnimac").first else { exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
let wanted = CommandLine.arguments.dropFirst().first ?? ""
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
var found = false
func walk(_ e: AXUIElement, _ depth: Int) {
    if found || depth > 8 { return }
    let title = (attr(e, "AXTitle") as? String) ?? ""
    if title.contains(wanted), (attr(e, "AXRole") as? String) == "AXMenuItem" {
        AXUIElementPerformAction(e, "AXPress" as CFString); found = true
        print("pulsado «\(title)»"); return
    }
    for kid in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(kid, depth + 1) }
}
walk(ax, 0)
if !found { print("no encontrado: \(wanted)") }
