import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import Vision

/// Selecciona una zona de la pantalla y copia el texto que contiene (OCR con Vision),
/// como TextSniper. Usa el permiso de Grabación de pantalla.
final class ScreenTextCapture {
    private var overlay: SelectionOverlayWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    func begin() {
        guard overlay == nil else { return }
        guard Permissions.hasScreenRecording else {
            _ = Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
            Toast.show("Necesita el permiso de Grabación de pantalla", symbol: "rectangle.dashed.badge.record")
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        let window = SelectionOverlayWindow(screen: screen)
        window.onSelect = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
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

    private func finish(rect: CGRect, screen: NSScreen) {
        dismiss()
        guard rect.width > 4, rect.height > 4 else { return }
        // Un instante para que el velo desaparezca antes de capturar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task.detached(priority: .userInitiated) {
                await Self.capture(rect: rect, screen: screen)
            }
        }
    }

    private static func capture(rect: CGRect, screen: NSScreen) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            // De coordenadas de Cocoa (origen abajo-izquierda) a las de la pantalla (arriba-izquierda).
            let local = CGRect(x: rect.minX - screen.frame.minX,
                               y: screen.frame.maxY - rect.maxY,
                               width: rect.width,
                               height: rect.height)
            configuration.sourceRect = local
            configuration.width = Int(local.width * scale)
            configuration.height = Int(local.height * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let text = try recognizeText(in: image)
            await MainActor.run {
                guard !text.isEmpty else {
                    Toast.show("No he encontrado texto en esa zona", symbol: "text.viewfinder")
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                let lines = text.split(separator: "\n").count
                Toast.show(lines == 1 ? "Texto copiado" : "Texto copiado · \(lines) líneas", symbol: "doc.on.clipboard.fill")
            }
        } catch {
            await MainActor.run {
                Toast.show("No se pudo capturar la pantalla", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        // Orden de lectura: de arriba abajo (Vision usa origen abajo-izquierda), de izquierda a derecha.
        let sorted = observations.sorted { a, b in
            let ay = a.boundingBox.midY, by = b.boundingBox.midY
            if abs(ay - by) > 0.012 { return ay > by }
            return a.boundingBox.minX < b.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

/// Velo con cruceta: arrastra para elegir la zona.
final class SelectionOverlayWindow: NSWindow {
    var onSelect: ((CGRect) -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.14)
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let origin = screen.frame.origin
        view.onSelect = { [weak self] rect in
            self?.onSelect?(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    func present() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }
}

final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let rect = selection
        start = nil
        current = nil
        needsDisplay = true
        if let rect { onSelect?(rect) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let hint = "Selecciona el texto a copiar · Esc para cancelar"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = hint.size(withAttributes: attributes)
        let pill = CGRect(x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - 110,
                          width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        hint.draw(at: CGPoint(x: pill.minX + 16, y: pill.minY + 8), withAttributes: attributes)

        guard let rect = selection else { return }
        NSColor.white.withAlphaComponent(0.14).setFill()
        rect.fill()
        NSColor(Brand.accent).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        label.draw(at: CGPoint(x: rect.minX, y: rect.maxY + 4), withAttributes: labelAttributes)
    }
}
