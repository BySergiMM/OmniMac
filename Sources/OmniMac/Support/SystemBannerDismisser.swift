import AppKit
import ApplicationServices

/// El aviso de «AirPods conectados» de macOS lo dibuja Control Center y no tiene
/// ajuste para desactivarlo. Con Accesibilidad, durante unos segundos buscamos esa
/// ventanita (pequeña, arriba a la derecha) y pulsamos su botón de cerrar.
/// Solo se pulsa un botón cuyo nombre sea cerrar/descartar: nunca otro control.
enum SystemBannerDismisser {
    private static let closeWords = ["cerrar", "close", "descartar", "dismiss", "ocultar", "hide"]

    static func dismissSoon(for seconds: TimeInterval = 7) {
        guard Permissions.hasAccessibility else { return }
        let deadline = Date().addingTimeInterval(seconds)
        func tick() {
            if attempt() || Date() > deadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: tick)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: tick)
    }

    private static func attempt() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { return false }
        for window in windows {
            guard let frame = frame(of: window), frame.height < 240, frame.width < 600, frame.minY < 140 else { continue }
            if let button = closeButton(in: window, depth: 0) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                NSLog("OmniMac: aviso de Control Center cerrado (\(Int(frame.width))×\(Int(frame.height)))")
                return true
            }
            // Sin botón visible: algunos avisos aceptan «cancelar».
            if AXUIElementPerformAction(window, kAXCancelAction as CFString) == .success {
                NSLog("OmniMac: aviso de Control Center cancelado")
                return true
            }
        }
        return false
    }

    private static func closeButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 7, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            let role = attribute(child, kAXRoleAttribute) as? String
            if role == kAXButtonRole as String {
                let words = [attribute(child, kAXTitleAttribute), attribute(child, kAXDescriptionAttribute), attribute(child, kAXHelpAttribute)]
                    .compactMap { $0 as? String }.joined(separator: " ").lowercased()
                if closeWords.contains(where: { words.contains($0) }) { return child }
            }
            if let found = closeButton(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        return CGRect(origin: point, size: dimensions)
    }
}
