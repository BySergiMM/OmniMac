import AppKit
import ApplicationServices
// Pulsa el icono de OmniMac en la barra de menús por accesibilidad (su posición en
// pantalla se mueve cuando macOS añade el indicador de grabación).
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.seergiii.omnimac").first else { exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
var barRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &barRef) == .success || AXUIElementCopyAttributeValue(ax, "AXMenuBar" as CFString, &barRef) == .success else { print("sin barra"); exit(1) }
var kids: CFTypeRef?
AXUIElementCopyAttributeValue(barRef as! AXUIElement, "AXChildren" as CFString, &kids)
guard let items = kids as? [AXUIElement] else { print("sin items"); exit(1) }
let wanted = CommandLine.arguments.dropFirst().first ?? "OmniMac"
for item in items {
    var d: CFTypeRef?
    AXUIElementCopyAttributeValue(item, "AXDescription" as CFString, &d)
    let name = (d as? String) ?? ""
    if name.contains(wanted) {
        AXUIElementPerformAction(item, "AXPress" as CFString)
        print("pulsado «\(name)»"); exit(0)
    }
}
print("no encontrado: \(items.count) items")
