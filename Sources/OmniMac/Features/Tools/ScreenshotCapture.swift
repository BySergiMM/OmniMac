import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Capturas de pantalla al portapapeles: una zona, o una zona con todo lo que hay al
/// desplazarla (una web entera, una conversación larga).
///
/// La de zona hace lo mismo que ⌃⇧⌘4 de macOS, pero con el velo del resto de
/// utilidades. La que vale la pena es la de scroll: macOS no la tiene.
final class ScreenshotCapture {
    enum Mode { case area, scrolling }

    private var overlay: SelectionOverlayWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var session: ScrollingSession?

    var isBusy: Bool { overlay != nil || session != nil }

    func begin(_ mode: Mode) {
        guard !isBusy else { return }
        guard Permissions.hasScreenRecording else {
            _ = Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
            Toast.show(L("Necesita el permiso de Grabación de pantalla", "Needs the Screen Recording permission"), symbol: "rectangle.dashed.badge.record")
            return
        }
        // Para desplazar el contenido hay que mandar la rueda del ratón a otra app.
        if mode == .scrolling, !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
            Toast.show(L("La captura con scroll necesita Accesibilidad", "Scrolling capture needs Accessibility"), symbol: "hand.raised.fill")
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        previousApp = NSWorkspace.shared.frontmostApplication

        let hint = mode == .area
            ? L("Selecciona la zona a capturar · Esc para cancelar", "Select the area to capture · Esc to cancel")
            : L("Selecciona la zona que se desplaza · Esc para cancelar", "Select the area that scrolls · Esc to cancel")
        let window = SelectionOverlayWindow(screen: screen, hint: hint)
        window.onSelect = { [weak self] rect in self?.selected(rect, on: screen, mode: mode) }
        overlay = window
        window.present()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            self?.closeOverlay()
            return nil
        }
    }

    private func closeOverlay() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        overlay?.orderOut(nil)
        overlay = nil
        // De vuelta a la app que estabas usando: es la que va a recibir la rueda.
        previousApp?.activate()
    }

    private func selected(_ rect: CGRect, on screen: NSScreen, mode: Mode) {
        closeOverlay()
        guard rect.width > 4, rect.height > 4 else { return }
        switch mode {
        case .area:
            // Un instante para que el velo desaparezca antes de capturar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Task { @MainActor in
                    do {
                        let image = try await ScreenGrab.image(of: rect, on: screen)
                        Self.copy(image, symbol: "camera.viewfinder")
                    } catch {
                        Toast.show(L("No se pudo capturar la pantalla", "Couldn't capture the screen"), symbol: "exclamationmark.triangle.fill")
                    }
                }
            }
        case .scrolling:
            // Más tiempo: la app de debajo tiene que volver a ser la de delante.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                let session = ScrollingSession(rect: rect, screen: screen)
                self?.session = session
                session.onFinish = { [weak self] in self?.session = nil }
                session.start()
            }
        }
    }

    /// Al portapapeles, como PNG y como imagen normal (TIFF) para las apps antiguas.
    @MainActor
    static func copy(_ image: CGImage, symbol: String) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        Toast.show(L("Captura copiada · \(image.width)×\(image.height) px",
                     "Screenshot copied · \(image.width)×\(image.height) px"),
                   symbol: symbol)
    }
}

// MARK: - Captura con scroll

/// Una captura con scroll en marcha: desplaza, captura, cose y vuelta a empezar.
@MainActor
private final class ScrollingSession {
    let rect: CGRect
    let screen: NSScreen
    var onFinish: (() -> Void)?

    /// Topes: una página infinita (un muro de una red social) no tiene final.
    static let maxFrames = 60
    static let maxPixelHeight = 20_000

    private var frames: [CGImage] = []
    private var signatures: [ScrollStitcher.Signature] = []
    /// La franja de la derecha de las dos últimas, para saber si se ve la barra de scroll.
    private var edges: [ScrollStitcher.Signature] = []
    private var steps: [ScrollStitcher.Step] = []
    private var stillCount = 0
    private var stopRequested = false
    private var border: NSWindow?
    private var hud: NSPanel?
    private var monitors: [Any] = []

    init(rect: CGRect, screen: NSScreen) {
        self.rect = rect
        self.screen = screen
    }

    /// Lo que se desplaza en cada paso: algo más de la mitad de la zona, para que el
    /// solape sea grande y se encuentre seguro.
    ///
    /// Cuando ya se sabe cuánto miden la cabecera y el pie fijos, el 70 % de lo que se
    /// mueve: menos pasos y el solape sigue siendo de sobra.
    private var stepPoints: CGFloat {
        guard let last = steps.last(where: { $0.shift > 0 }) else { return max(40, (rect.height * 0.55).rounded()) }
        let moving = rect.height - CGFloat(last.top + last.bottom) / screen.backingScaleFactor
        return max(40, (moving * 0.7).rounded())
    }

    func start() {
        showChrome()
        Task { await run() }
    }

    func requestStop() { stopRequested = true }

    private func run() async {
        do {
            try await capture()
            while !stopRequested, frames.count < Self.maxFrames, stitchedHeight < Self.maxPixelHeight {
                scroll()
                // Un segundo entero: la barra de desplazamiento flotante de macOS sale con
                // cada scroll y se va a los 0,7–0,9 s (medido en Safari, macOS 27). Con
                // menos espera dejaba un trozo pegado al borde en cada tramo, y no se puede
                // detectar siempre: cuando cae en la parte nueva no hay con qué compararla.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !stopRequested else { break }
                try await capture()
                guard let previous = signatures.dropLast().last else { break }
                let expected = Int(stepPoints * screen.backingScaleFactor)
                var found = signatures.last.flatMap { ScrollStitcher.step(from: previous, to: $0, expected: expected) }
                // Por si una app la deja más rato: si en la parte que se solapa aparece algo
                // en el borde que antes no estaba, se repite la captura (como mucho 1,6 s).
                var tries = 0
                while let step = found, let before = edges.first, let after = edges.last,
                      !ScrollStitcher.trailingMatches(before, after, step: step), tries < 8 {
                    tries += 1
                    try await Task.sleep(nanoseconds: 200_000_000)
                    frames.removeLast(); signatures.removeLast(); edges.removeLast()
                    try await capture()
                    found = signatures.last.flatMap { ScrollStitcher.step(from: previous, to: $0, expected: expected) }
                }
                guard let step = found else {
                    // No encaja: se queda lo que ya estaba cosido y se descarta la última.
                    frames.removeLast()
                    break
                }
                steps.append(step)
                if step.shift == 0 {
                    // Dos veces sin moverse: final de la página.
                    stillCount += 1
                    if stillCount >= 2 { break }
                } else {
                    stillCount = 0
                }
            }
            finish()
        } catch {
            hideChrome()
            Toast.show(L("No se pudo capturar la pantalla", "Couldn't capture the screen"), symbol: "exclamationmark.triangle.fill")
            onFinish?()
        }
    }

    private var stitchedHeight: Int {
        guard let height = frames.first?.height else { return 0 }
        return ScrollStitcher.pieces(height: height, steps: steps).reduce(0) { $0 + $1.rows.count }
    }

    private func capture() async throws {
        // Fuera el marco y el aviso: son de OmniMac y se excluyen de la imagen.
        let image = try await ScreenGrab.image(of: rect, on: screen, excludingOwnWindows: true)
        // Sin el borde derecho, donde sale y se va la barra de desplazamiento flotante.
        let scrollbar = Int(24 * screen.backingScaleFactor)
        guard let signature = ScrollStitcher.signature(of: image, ignoringTrailing: scrollbar),
              let edge = ScrollStitcher.trailingSignature(of: image, trailing: scrollbar) else { throw CocoaError(.coderInvalidValue) }
        frames.append(image)
        signatures.append(signature)
        edges.append(edge)
        if edges.count > 2 { edges.removeFirst(edges.count - 2) }
        // Para coser solo hacen falta las dos últimas; cada firma es un mega.
        if signatures.count > 2 { signatures.removeFirst(signatures.count - 2) }
    }

    /// Una vuelta de rueda en píxeles, en el centro de la zona. El puntero se lleva
    /// ahí antes: la rueda va a la ventana que hay bajo él.
    private func scroll() {
        // De Cocoa (origen abajo, en la pantalla principal) a Quartz (origen arriba).
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let center = CGPoint(x: rect.midX, y: primaryTop - rect.midY)
        CGWarpMouseCursorPosition(center)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: Int32(-stepPoints), wheel2: 0, wheel3: 0)
        event?.location = center
        event?.post(tap: .cghidEventTap)
    }

    private func finish() {
        hideChrome()
        defer { onFinish?() }
        guard let first = frames.first else { return }
        let pieces = ScrollStitcher.pieces(height: first.height, steps: Array(steps.prefix(frames.count - 1)))
        guard let image = Self.compose(frames: frames, pieces: pieces) else {
            Toast.show(L("No se pudo montar la captura", "Couldn't put the screenshot together"), symbol: "exclamationmark.triangle.fill")
            return
        }
        ScreenshotCapture.copy(image, symbol: "scroll")
    }

    /// Dibuja los trozos uno debajo de otro.
    static func compose(frames: [CGImage], pieces: [ScrollStitcher.Piece]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let height = pieces.reduce(0) { $0 + $1.rows.count }
        guard height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var top = 0
        for piece in pieces where frames.indices.contains(piece.frame) {
            // `cropping` cuenta desde arriba; el contexto, desde abajo.
            let crop = CGRect(x: 0, y: piece.rows.lowerBound, width: width, height: piece.rows.count)
            if let strip = frames[piece.frame].cropping(to: crop) {
                context.draw(strip, in: CGRect(x: 0, y: height - top - piece.rows.count, width: width, height: piece.rows.count))
            }
            top += piece.rows.count
        }
        return context.makeImage()
    }

    // MARK: Marco y aviso

    private func showChrome() {
        // Un marco alrededor de la zona, que no se come los clics ni la rueda.
        let frameWindow = NSWindow(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: .borderless, backing: .buffered, defer: false)
        frameWindow.isOpaque = false
        frameWindow.backgroundColor = .clear
        frameWindow.ignoresMouseEvents = true
        frameWindow.level = .statusBar
        frameWindow.collectionBehavior = [.canJoinAllSpaces, .transient]
        let outline = NSView(frame: NSRect(origin: .zero, size: frameWindow.frame.size))
        outline.wantsLayer = true
        outline.layer?.borderColor = NSColor(Brand.accent).cgColor
        outline.layer?.borderWidth = 2
        outline.layer?.cornerRadius = 4
        frameWindow.contentView = outline
        frameWindow.orderFrontRegardless()
        border = frameWindow

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 36),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        let host = NSHostingView(rootView: ScrollingHUD { [weak self] in self?.requestStop() })
        panel.contentView = host
        let size = host.fittingSize
        // Debajo de la zona si cabe; si no, encima.
        let below = rect.minY - size.height - 10
        let y = below > screen.visibleFrame.minY ? below : min(rect.maxY + 10, screen.visibleFrame.maxY - size.height)
        panel.setFrame(NSRect(x: rect.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        hud = panel

        // Esc para parar. Global: la app de delante es la que se desplaza. Con un clic
        // no: caería en la página y podría abrir un enlace.
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) { Task { @MainActor in self?.requestStop() } }
        }) { monitors.append(keys) }
    }

    private func hideChrome() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        border?.orderOut(nil)
        hud?.orderOut(nil)
        border = nil
        hud = nil
    }
}

/// «Capturando con scroll · Esc para parar», con un botón «Listo».
private struct ScrollingHUD: View {
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(L("Capturando con scroll · Esc para parar", "Scrolling capture · Esc to stop"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Button(L("Listo", "Done"), action: onStop)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .fixedSize()
    }
}
