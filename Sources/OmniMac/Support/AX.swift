import AppKit
import ApplicationServices

/// API privada pero estable que usan AltTab, yabai, etc. para obtener el CGWindowID
/// de una ventana de Accesibilidad.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Ayudas para trabajar con la API de Accesibilidad.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool {
        (attribute(element, name) as? Bool) ?? false
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = attribute(element, name), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        let array = value as! [AnyObject]
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    static func set(_ element: AXUIElement, _ name: String, to value: CFTypeRef) {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    static func setPoint(_ element: AXUIElement, _ name: String, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            set(element, name, to: value)
        }
    }

    static func setSize(_ element: AXUIElement, _ name: String, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            set(element, name, to: value)
        }
    }

    /// Coloca una ventana en un rect de Cocoa. Posición → tamaño → posición: algunas
    /// apps recolocan la ventana al redimensionar, así que fijamos el origen al final.
    static func setFrame(_ window: AXUIElement, cocoaRect: CGRect) {
        let origin = flip(cocoaRect).origin
        setPoint(window, kAXPositionAttribute as String, origin)
        setSize(window, kAXSizeAttribute as String, cocoaRect.size)
        setPoint(window, kAXPositionAttribute as String, origin)
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    /// Convierte un rect en coordenadas de Cocoa (origen abajo-izquierda) a
    /// coordenadas de Accesibilidad (origen arriba-izquierda de la pantalla principal).
    static func flip(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
