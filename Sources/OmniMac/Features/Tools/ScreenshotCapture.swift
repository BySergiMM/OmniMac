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
        // Otra vez ⇧⌘8 (o el menú) con una captura con scroll en marcha: «Listo».
        if mode == .scrolling, let session {
            // Los atajos y el menú llegan siempre por el hilo principal.
            MainActor.assumeIsolated { session.finishNow() }
            return
        }
        guard !isBusy else { return }
        guard Permissions.hasScreenRecording else {
            _ = Permissions.requestScreenRecording()
            Permissions.openScreenRecordingSettings()
            Toast.show(L("Necesita el permiso de Grabación de pantalla", "Needs the Screen Recording permission"), symbol: "rectangle.dashed.badge.record")
            return
        }
        // Para oír Esc mientras te desplazas por otra app hace falta Accesibilidad.
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
        // De vuelta a la app que estabas usando: es la que vas a desplazar.
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
            // Un instante para que el velo desaparezca antes de la primera captura.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                let session = ScrollingSession(rect: rect, screen: screen)
                self?.session = session
                session.onFinish = { [weak self] in self?.session = nil }
                session.start()
            }
        }
    }

    /// Al portapapeles, como PNG y como imagen normal (TIFF) para las apps antiguas.
    @MainActor
    static func copy(_ image: CGImage, symbol: String, note: String? = nil) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if let note {
            Toast.show(L("Captura copiada, \(note)", "Screenshot copied, \(note)"), symbol: symbol, duration: 4)
        } else {
            Toast.show(L("Captura copiada · \(image.width)×\(image.height) px",
                         "Screenshot copied · \(image.width)×\(image.height) px"),
                       symbol: symbol)
        }
    }
}

// MARK: - Captura con scroll

/// Lo que enseña el aviso mientras capturas: cuánto llevas.
@MainActor
private final class ScrollingStatus: ObservableObject {
    @Published var pixels = 0
    /// Te has movido tan deprisa que la última captura quieta ya no se solapa con lo
    /// cosido: hay que volver un poco atrás.
    @Published var lost = false
}

/// Una captura con scroll en marcha. **Te desplazas tú**: OmniMac no mueve nada, va
/// capturando la zona mientras bajas o subes a tu ritmo, cose lo que pasa por ella y para
/// cuando pulsas «Listo» (o otra vez ⇧⌘8). Esc cancela.
///
/// Antes desplazaba OmniMac sola, y en cuanto elegías la zona la pantalla se movía sin
/// que supieras hacia dónde: funcionaba, pero no se entendía.
@MainActor
final class ScrollingSession {
    let rect: CGRect
    let screen: NSScreen
    var onFinish: (() -> Void)?

    /// Tope: una página infinita (un muro de una red social) no tiene final.
    static let maxPixelHeight = 20_000

    private struct Stored {
        let image: CGImage
        /// Filas respecto a la primera captura (negativo si subiste).
        let offset: Int
        /// Hecha con el contenido quieto: sin la barra de desplazamiento.
        let clean: Bool
    }

    private var stored: [Stored] = []
    /// La más alejada por cada lado que aún no se ha guardado: siempre entra al final.
    private var topEdge: Stored?
    private var bottomEdge: Stored?
    /// La última captura que encajó: con ella se compara la siguiente.
    private var reference: (signature: ScrollStitcher.Signature, offset: Int)?
    /// La captura anterior, cosida o no: si la nueva sale igual, el contenido está quieto.
    private var lastProbe: ScrollStitcher.Signature?
    /// Desde cuándo no encaja ninguna captura quieta (para no avisar por un instante).
    private var failingSince: Date?
    private var moves: [ScrollStitcher.Step] = []
    private var signatureColumns = 0
    private var timer: Timer?
    private var lastScrollAt: Date?
    private var cleanCapturedFor: Date?
    private var lastCaptureAt = Date.distantPast
    private var capturing = false
    private var done = false
    private let status = ScrollingStatus()
    private var border: NSWindow?
    private var hud: NSPanel?
    private var monitors: [Any] = []

    init(rect: CGRect, screen: NSScreen) {
        self.rect = rect
        self.screen = screen
    }

    func start() {
        showChrome()
        capture(clean: true)
        // Solo existe mientras dura la captura.
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// «Listo» u otra vez ⇧⌘8: se monta lo que haya.
    func finishNow() {
        guard !done else { return }
        done = true
        timer?.invalidate()
        timer = nil
        Task { @MainActor in
            while capturing { try? await Task.sleep(nanoseconds: 40_000_000) }
            // Si soltaste justo antes de pulsar, la última posición aún no está.
            if let last = lastScrollAt, lastCaptureAt < last { await grab(clean: false) }
            finish()
        }
    }

    /// Esc: fuera, sin copiar nada.
    func cancel() {
        guard !done else { return }
        done = true
        timer?.invalidate()
        timer = nil
        hideChrome()
        Toast.show(L("Captura cancelada", "Capture cancelled"), symbol: "xmark.circle")
        onFinish?()
    }

    /// Mientras te mueves (y un rato después), una captura cada ~0,1 s para pillar los
    /// momentos en que el contenido se queda quieto; al parar un segundo, una limpia.
    private func tick() {
        guard !capturing, !done, let last = lastScrollAt else { return }
        let now = Date()
        let idle = now.timeIntervalSince(last)
        if idle < 0.9 {
            if now.timeIntervalSince(lastCaptureAt) >= 0.1 { capture(clean: false) }
        } else if idle >= 1.0, cleanCapturedFor != last {
            // La barra de desplazamiento flotante se va a los 0,7–0,9 s de parar.
            cleanCapturedFor = last
            capture(clean: true)
        }
    }

    private func capture(clean: Bool) {
        capturing = true
        lastCaptureAt = Date()
        Task { @MainActor in
            await grab(clean: clean)
            capturing = false
        }
    }

    private func grab(clean: Bool) async {
        lastCaptureAt = Date()
        // Fuera el marco y el aviso: son de OmniMac y se excluyen de la imagen.
        guard let image = try? await ScreenGrab.image(of: rect, on: screen, excludingOwnWindows: true) else { return }
        process(image, clean: clean)
    }

    private func process(_ image: CGImage, clean: Bool) {
        // Sin el borde derecho, donde sale y se va la barra de desplazamiento flotante.
        let scrollbar = Int(24 * screen.backingScaleFactor)
        guard let signature = ScrollStitcher.signature(of: image, ignoringTrailing: scrollbar) else { return }
        signatureColumns = signature.columns
        let edge = scrollbarColumns(imageWidth: image.width)
        // Solo se cose con el contenido quieto: Safari, Chrome o Claude animan el
        // desplazamiento, y a mitad de la animación el texto cae en medio píxel y se
        // dibuja distinto, así que ninguna fila encaja. Quieto = igual que la anterior.
        let settled = clean || lastProbe.map { ScrollStitcher.samePlace($0, signature, ignoring: edge) } ?? true
        lastProbe = signature
        guard settled else { return }
        guard let reference else {
            self.reference = (signature, 0)
            stored.append(Stored(image: image, offset: 0, clean: clean))
            status.pixels = image.height
            return
        }
        var offset: Int?
        if ScrollStitcher.samePlace(reference.signature, signature, ignoring: edge) {
            offset = reference.offset
        } else if let down = ScrollStitcher.step(from: reference.signature, to: signature, edgeColumns: edge) {
            offset = reference.offset + down.shift
            if down.shift > 0 { moves.append(down) }
        } else if let up = ScrollStitcher.step(from: signature, to: reference.signature, edgeColumns: edge), up.shift > 0 {
            offset = reference.offset - up.shift
            moves.append(up)
        }
        // No encaja (te has movido demasiado rápido entre dos capturas, o algo cambió):
        // se descarta y la siguiente se compara con la última buena. Volviendo un poco
        // atrás, sigue cosiendo.
        guard let offset else {
            // Con la rueda, dos golpes seguidos sin pararse entre medias fallan un momento
            // y la siguiente encaja: solo se avisa si dura.
            let since = failingSince ?? Date()
            failingSince = since
            if Date().timeIntervalSince(since) > 0.7 { status.lost = true }
            return
        }
        failingSince = nil
        status.lost = false
        self.reference = (signature, offset)
        keep(Stored(image: image, offset: offset, clean: clean))
        status.pixels = coveredHeight
        if coveredHeight >= Self.maxPixelHeight { finishNow() }
    }

    /// Cabecera y pie fijos que se han visto, con tope: más de un cuarto ya no es una barra.
    private func fixedBars(height: Int) -> (top: Int, bottom: Int) {
        let cap = height / 4
        return (min(cap, moves.map(\.top).max() ?? 0), min(cap, moves.map(\.bottom).max() ?? 0))
    }

    /// Se guarda lo que hace falta: lo que amplía lo cubierto (cada tercio de la parte que
    /// se mueve, y siempre la última por cada lado) y las capturas limpias. Las demás, a
    /// ocho por segundo, llenarían la memoria sin aportar nada.
    private func keep(_ new: Stored) {
        if let index = stored.firstIndex(where: { abs($0.offset - new.offset) <= 2 }) {
            if new.clean, !stored[index].clean { stored[index] = new }
            return
        }
        let bars = fixedBars(height: new.image.height)
        let spacing = max(1, (new.image.height - bars.top - bars.bottom) / 3)
        guard let lowest = stored.map(\.offset).min(), let highest = stored.map(\.offset).max() else {
            stored.append(new)
            return
        }
        if new.offset > highest {
            if new.offset - highest >= spacing, let edge = bottomEdge, edge.offset > highest {
                stored.append(edge)
                bottomEdge = nil
            }
            let top = stored.map(\.offset).max() ?? highest
            if new.clean || new.offset - top >= spacing { stored.append(new); bottomEdge = nil } else { bottomEdge = new }
        } else if new.offset < lowest {
            if lowest - new.offset >= spacing, let edge = topEdge, edge.offset < lowest {
                stored.append(edge)
                topEdge = nil
            }
            let bottom = stored.map(\.offset).min() ?? lowest
            if new.clean || bottom - new.offset >= spacing { stored.append(new); topEdge = nil } else { topEdge = new }
        } else if new.clean {
            stored.append(new)
        }
    }

    private var coveredHeight: Int {
        let offsets = stored.map(\.offset) + [topEdge, bottomEdge].compactMap { $0?.offset }
        guard let lowest = offsets.min(), let highest = offsets.max(), let height = stored.first?.image.height else { return 0 }
        return highest - lowest + height
    }

    private func finish() {
        hideChrome()
        defer { onFinish?() }
        for edge in [topEdge, bottomEdge].compactMap({ $0 }) where !stored.contains(where: { $0.offset == edge.offset }) {
            stored.append(edge)
        }
        guard let first = stored.first else { return }
        let bars = fixedBars(height: first.image.height)
        let plan = ScrollStitcher.layout(offsets: stored.map(\.offset), clean: stored.map(\.clean),
                                         height: first.image.height, top: bars.top, bottom: bars.bottom)
        let columns = ScrollStitcher.keptColumns(moves)
        let xRange = columns.map { pixelRange($0, imageWidth: first.image.width) } ?? 0..<first.image.width
        guard let image = Self.compose(images: stored.map(\.image), plan: plan, xRange: xRange) else {
            Toast.show(L("No se pudo montar la captura", "Couldn't put the screenshot together"), symbol: "exclamationmark.triangle.fill")
            return
        }
        if moves.isEmpty {
            // Se copia lo que se ve, pero se dice: si no, parece que no ha funcionado.
            ScreenshotCapture.copy(image, symbol: "scroll", note: L("no te has desplazado: solo lo visible",
                                                                      "you didn't scroll: visible part only"))
        } else {
            ScreenshotCapture.copy(image, symbol: "scroll")
        }
    }

    /// La barra de desplazamiento ocupa unos 24 puntos; en columnas de la firma.
    private func scrollbarColumns(imageWidth: Int) -> Int {
        let measured = imageWidth - Int(24 * screen.backingScaleFactor)
        guard measured > 0, signatureColumns > 0 else { return 0 }
        return Int((24 * screen.backingScaleFactor * CGFloat(signatureColumns) / CGFloat(measured)).rounded(.up))
    }

    /// De columnas de la firma a píxeles de la captura. La firma no mira el borde
    /// derecho (la barra de desplazamiento): si el recorte llega al final, llega hasta
    /// el borde de verdad.
    private func pixelRange(_ kept: Range<Int>, imageWidth: Int) -> Range<Int> {
        let measured = imageWidth - Int(24 * screen.backingScaleFactor)
        let count = signatureColumns
        guard count > 0, measured > 0 else { return 0..<imageWidth }
        let lower = kept.lowerBound * measured / count
        let upper = kept.upperBound >= count ? imageWidth : (kept.upperBound * measured + count - 1) / count
        return max(0, lower)..<min(imageWidth, max(lower + 1, upper))
    }

    /// Pinta los trozos donde dice el plan, por capas.
    static func compose(images: [CGImage], plan: (height: Int, draws: [ScrollStitcher.Draw]), xRange: Range<Int>) -> CGImage? {
        guard let first = images.first, plan.height > 0 else { return nil }
        let width = xRange.count
        guard let context = CGContext(data: nil, width: width, height: plan.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for draw in plan.draws where images.indices.contains(draw.frame) {
            // `cropping` cuenta desde arriba; el contexto, desde abajo.
            let crop = CGRect(x: xRange.lowerBound, y: draw.rows.lowerBound, width: width, height: draw.rows.count)
            guard let strip = images[draw.frame].cropping(to: crop) else { continue }
            context.draw(strip, in: CGRect(x: 0, y: plan.height - draw.y - draw.rows.count, width: width, height: draw.rows.count))
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
        let host = NSHostingView(rootView: ScrollingHUD(status: status, onDone: { [weak self] in self?.finishNow() }))
        panel.contentView = host
        let size = CGSize(width: max(host.fittingSize.width, 420), height: host.fittingSize.height)
        // Debajo de la zona si cabe; si no, encima.
        let below = rect.minY - size.height - 10
        let y = below > screen.visibleFrame.minY ? below : min(rect.maxY + 10, screen.visibleFrame.maxY - size.height)
        panel.setFrame(NSRect(x: rect.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        hud = panel

        // Cuándo te desplazas (para capturar justo entonces) y Esc para cancelar.
        // Globales: la app de delante es la que se desplaza. Intro no: en un chat
        // enviaría el mensaje.
        if let wheel = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] _ in
            Task { @MainActor in self?.lastScrollAt = Date() }
        }) { monitors.append(wheel) }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) { Task { @MainActor in self?.cancel() } }
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

/// «Desplázate por la zona · 3.400 px», con un botón «Listo».
private struct ScrollingHUD: View {
    @ObservedObject var status: ScrollingStatus
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Desplázate por la zona", "Scroll through the area"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if status.lost {
                    Text(L("Muy rápido: vuelve un poco atrás", "Too fast: scroll back a little"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(L("\(status.pixels) px · Esc cancela", "\(status.pixels) px · Esc cancels"))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            Button(L("Listo", "Done"), action: onDone)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .fixedSize()
    }
}
