import AppKit
import ApplicationServices

/// Permisos del sistema (Accesibilidad y Grabación de pantalla): comprobar si los tenemos y pedirlos.
enum Permissions {
    /// Permiso de Accesibilidad: necesario para el selector ⌘Tab, mover ventanas
    /// y simular el pegado del portapapeles.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Muestra el diálogo del sistema pidiendo el permiso.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Permiso de Grabación de pantalla: necesario para las miniaturas en vivo del
    /// selector de ventanas (como AltTab). Sin él, el selector usa el icono de la app.
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Observa el permiso de Accesibilidad SOLO mientras la ventana de Ajustes está
/// abierta (antes el temporizador de la vista vivía para siempre).
final class PermissionsMonitor: ObservableObject {
    static let shared = PermissionsMonitor()

    @Published private(set) var accessibilityGranted = Permissions.hasAccessibility
    @Published private(set) var screenRecordingGranted = Permissions.hasScreenRecording

    private var timer: Timer?

    private init() {}

    func startWatching() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let granted = Permissions.hasAccessibility
        if granted != accessibilityGranted {
            accessibilityGranted = granted
            if granted {
                FeatureManager.shared.accessibilityGranted()
            }
        }
        let screen = Permissions.hasScreenRecording
        if screen != screenRecordingGranted {
            screenRecordingGranted = screen
        }
    }
}
