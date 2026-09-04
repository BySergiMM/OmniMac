import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Selector de color: haz clic en cualquier punto de la pantalla y el color va al
/// portapapeles en hexadecimal (#3A7BD5). Usa el permiso de Grabación de pantalla.
final class ScreenColorPicker {
    private var overlay: ColorPickOverlayWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    func begin() {
        guard overlay == nil else { return }
        guard Permissions.hasScreenRecording else {
            _ = Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
            Toast.show(L("Necesita el permiso de Grabación de pantalla", "Needs the Screen Recording permission"), symbol: "rectangle.dashed.badge.record")
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        let window = ColorPickOverlayWindow(screen: screen)
        window.onPick = { [weak self] point in self?.finish(point: point, screen: screen) }
        overlay = window
        window.present()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        overlay?.orderOut(nil)
        overlay = nil
        previousApp?.activate()
        previousApp = nil
    }

    private func finish(point: CGPoint, screen: NSScreen) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task.detached(priority: .userInitiated) {
                await Self.pick(point: point, screen: screen)
            }
        }
    }

    private static func pick(point: CGPoint, screen: NSScreen) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            // 3×3 puntos alrededor del clic, en coordenadas de la pantalla (origen arriba-izquierda).
            let local = CGRect(x: point.x - screen.frame.minX - 1.5,
                               y: screen.frame.maxY - point.y - 1.5,
                               width: 3, height: 3)
            configuration.sourceRect = local
            configuration.width = Int(3 * scale)
            configuration.height = Int(3 * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let color = centerColor(of: image) else { return }
            let hex = String(format: "#%02X%02X%02X", color.r, color.g, color.b)
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hex, forType: .string)
                Toast.show(L("\(hex) copiado · rgb(\(color.r), \(color.g), \(color.b))", "\(hex) copied · rgb(\(color.r), \(color.g), \(color.b))"),
                           symbol: "eyedropper.halffull",
                           duration: 2.5,
                           tint: NSColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1))
            }
        } catch {
            await MainActor.run {
                Toast.show(L("No se pudo leer el color", "Couldn't read the colour"), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Píxel central de la captura, en sRGB de 8 bits.
    private static func centerColor(of image: CGImage) -> (r: Int, g: Int, b: Int)? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = ((height / 2) * width + width / 2) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }
}

/// Velo con cruceta: un clic elige el color.
final class ColorPickOverlayWindow: NSWindow {
    var onPick: ((CGPoint) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = ColorPickView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let origin = screen.frame.origin
        view.onPick = { [weak self] p in self?.onPick?(CGPoint(x: p.x + origin.x, y: p.y + origin.y)) }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    func present() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }
}

final class ColorPickView: NSView {
    var onPick: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseUp(with event: NSEvent) {
        onPick?(convert(event.locationInWindow, from: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        let hint = L("Haz clic en un color para copiarlo · Esc para cancelar", "Click a colour to copy it · Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        let size = hint.size(withAttributes: attributes)
        let pill = CGRect(x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - 110,
                          width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        hint.draw(at: CGPoint(x: pill.minX + 16, y: pill.minY + 8), withAttributes: attributes)
    }
}
