import AppKit
import ScreenCaptureKit

/// Captura miniaturas en vivo de las ventanas (como AltTab), usando ScreenCaptureKit.
/// Necesita permiso de Grabación de pantalla; si no está, devuelve nil y el selector
/// usa el icono de la app.
enum WindowThumbnails {
    /// Captura imágenes de un conjunto de CGWindowID a la vez. Devuelve un diccionario
    /// id → imagen (solo las que se pudieron capturar).
    static func capture(windowIDs: Set<CGWindowID>, maxDimension: CGFloat = 400) async -> [CGWindowID: NSImage] {
        guard !windowIDs.isEmpty else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            return [:]
        }
        let targets = content.windows.filter { windowIDs.contains($0.windowID) }

        var result: [CGWindowID: NSImage] = [:]
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for window in targets {
                group.addTask {
                    (window.windowID, await captureOne(window, maxDimension: maxDimension))
                }
            }
            for await (id, image) in group {
                if let image { result[id] = image }
            }
        }
        return result
    }

    private static func captureOne(_ window: SCWindow, maxDimension: CGFloat) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()

        let w = max(1, window.frame.width)
        let h = max(1, window.frame.height)
        let scale = min(1, maxDimension / max(w, h))
        config.width = Int(w * scale) * 2      // 2× para pantallas Retina
        config.height = Int(h * scale) * 2
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true

        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                        configuration: config) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
    }
}
