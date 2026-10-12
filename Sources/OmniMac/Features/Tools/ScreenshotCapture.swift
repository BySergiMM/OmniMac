import AppKit
import Carbon.HIToolbox
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

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
    /// Ninguna imagen encaja desde hace un rato (algo tapa la zona, o cambió de golpe):
    /// hay que volver un poco atrás.
    @Published var lost = false
}

/// Dónde cae cada imagen de la zona mientras te desplazas, y cuáles se guardan.
///
/// Vive en su propia cola (`queue`): el flujo de ScreenCaptureKit le entrega ~30
/// imágenes por segundo y todo el cálculo se hace ahí, sin frenar la app.
///
/// Cada imagen se compara con la anterior, **también en pleno movimiento**: a 30 por
/// segundo, aunque deslices rápido, el contenido avanza poco entre una y otra y siempre
/// hay solape. Antes solo se cosía con el contenido quieto (y con fotos sueltas, una cada
/// 0,16 s): había que desplazarse a trompicones, parando cada poco.
///
/// Todo su estado se toca solo desde `queue`; por eso se puede pasar entre hilos.
final class ScrollTracker: @unchecked Sendable {
    let queue = DispatchQueue(label: "omnimac.captura-scroll", qos: .userInitiated)
    /// La barra de desplazamiento ocupa unos 24 puntos: en píxeles, y en columnas de firma.
    let scrollbarPixels: Int
    var onProgress: ((Int, Bool) -> Void)?

    struct Stored {
        let image: CGImage
        /// Filas respecto a la primera imagen (negativo si subiste).
        let offset: Int
        /// Con el contenido quieto: sin la barra de desplazamiento.
        let clean: Bool
    }

    private(set) var stored: [Stored] = []
    private var topEdge: Stored?
    private var bottomEdge: Stored?
    private(set) var moves: [ScrollStitcher.Step] = []
    private(set) var signatureColumns = 0
    /// La anterior (para comparar con la siguiente) y la última que encajó.
    private var previous: (signature: ScrollStitcher.Signature, offset: Int)?
    private var lastGood: (signature: ScrollStitcher.Signature, offset: Int)?
    private var failingSince: Date?
    /// Cuándo te desplazaste por última vez (lo apunta el hilo principal, vía `queue`).
    var lastScrollAt: Date?
    private var cleanFor: Date?
    private var frames = 0

    init(scrollbarPixels: Int) {
        self.scrollbarPixels = scrollbarPixels
    }

    /// Un segundo después de tu último movimiento, la barra de desplazamiento ya se ha
    /// ido: esas imágenes son las «limpias».
    private var isQuiet: Bool {
        guard let lastScrollAt else { return true }
        return Date().timeIntervalSince(lastScrollAt) >= 1.0
    }

    func ingest(_ image: CGImage) {
        frames += 1
        guard let signature = ScrollStitcher.signature(of: image, ignoringTrailing: scrollbarPixels) else { return }
        signatureColumns = signature.columns
        let edge = scrollbarColumns(imageWidth: image.width)
        let clean = isQuiet
        guard let previous else {
            self.previous = (signature, 0)
            lastGood = (signature, 0)
            stored.append(Stored(image: image.copied(), offset: 0, clean: true))
            report()
            return
        }
        // Igual que la anterior: no se ha movido. Si ya es «limpia», sustituye a la que
        // tuviera la barra en esa posición.
        if ScrollStitcher.samePlace(previous.signature, signature, ignoring: edge) {
            self.previous = (signature, previous.offset)
            if clean, cleanFor != lastScrollAt {
                cleanFor = lastScrollAt
                keep(Stored(image: image.copied(), offset: previous.offset, clean: true))
                report()
            }
            return
        }
        let offset = place(signature, against: previous, edge: edge)
            ?? lastGood.flatMap { place(signature, against: $0, edge: edge) }
        guard let offset else {
            // Se sigue comparando con la última buena: volviendo atrás, se recupera.
            self.previous = lastGood
            let since = failingSince ?? Date()
            failingSince = since
            report(lost: Date().timeIntervalSince(since) > 0.7)
            return
        }
        failingSince = nil
        self.previous = (signature, offset)
        lastGood = (signature, offset)
        keep(Stored(image: image, offset: offset, clean: clean))
        report()
    }

    /// Dónde cae `signature` respecto a `base`: debajo o encima.
    private func place(_ signature: ScrollStitcher.Signature, against base: (signature: ScrollStitcher.Signature, offset: Int),
                       edge: Int) -> Int? {
        if let down = ScrollStitcher.step(from: base.signature, to: signature, edgeColumns: edge), down.shift > 0 {
            moves.append(down)
            return base.offset + down.shift
        }
        if let up = ScrollStitcher.step(from: signature, to: base.signature, edgeColumns: edge), up.shift > 0 {
            moves.append(up)
            return base.offset - up.shift
        }
        return nil
    }

    private func report(lost: Bool = false) {
        let pixels = coveredHeight
        onProgress?(pixels, lost)
    }

    /// Cabecera y pie fijos. Lo que más se repite entre los pasos: una barra fija de
    /// verdad sale igual en casi todos, y lo que cambia son filas que coincidieron por
    /// casualidad (de más) o una barra tapada un momento (de menos). Con el máximo
    /// quedaban franjas en blanco; con el mínimo, la cabecera se pegaba como contenido.
    func fixedBars(height: Int) -> (top: Int, bottom: Int) {
        let cap = height / 4
        func mostCommon(_ values: [Int]) -> Int {
            let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
            return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? 0
        }
        return (min(cap, mostCommon(moves.map(\.top))), min(cap, mostCommon(moves.map(\.bottom))))
    }

    /// Lo menos que se ha visto: si con lo habitual quedara algún hueco, se monta con esto.
    private func smallestBars(height: Int) -> (top: Int, bottom: Int) {
        let cap = height / 4
        return (min(cap, moves.map(\.top).min() ?? 0), min(cap, moves.map(\.bottom).min() ?? 0))
    }

    /// Se guarda lo que hace falta: lo que amplía lo cubierto (cada tercio de la parte que
    /// se mueve, y siempre la última por cada lado) y las limpias. Las demás, a 30 por
    /// segundo, llenarían la memoria sin aportar nada. Se guardan copiadas: las del flujo
    /// son búferes suyos, y retenerlas lo dejaría sin sitio para las siguientes.
    private func keep(_ new: Stored) {
        if let index = stored.firstIndex(where: { abs($0.offset - new.offset) <= 2 }) {
            if new.clean, !stored[index].clean { stored[index] = Stored(image: new.image.copied(), offset: new.offset, clean: true) }
            return
        }
        let bars = fixedBars(height: new.image.height)
        let spacing = max(1, (new.image.height - bars.top - bars.bottom) / 3)
        guard let lowest = stored.map(\.offset).min(), let highest = stored.map(\.offset).max() else {
            stored.append(Stored(image: new.image.copied(), offset: new.offset, clean: new.clean))
            return
        }
        let copy = { Stored(image: new.image.copied(), offset: new.offset, clean: new.clean) }
        if new.offset > highest {
            if new.offset - highest >= spacing, let edge = bottomEdge, edge.offset > highest {
                stored.append(edge)
                bottomEdge = nil
            }
            let top = stored.map(\.offset).max() ?? highest
            if new.clean || new.offset - top >= spacing { stored.append(copy()); bottomEdge = nil } else { bottomEdge = copy() }
        } else if new.offset < lowest {
            if lowest - new.offset >= spacing, let edge = topEdge, edge.offset < lowest {
                stored.append(edge)
                topEdge = nil
            }
            let bottom = stored.map(\.offset).min() ?? lowest
            if new.clean || bottom - new.offset >= spacing { stored.append(copy()); topEdge = nil } else { topEdge = copy() }
        } else if new.clean {
            stored.append(copy())
        }
    }

    var coveredHeight: Int {
        let offsets = stored.map(\.offset) + [topEdge, bottomEdge].compactMap { $0?.offset }
        guard let lowest = offsets.min(), let highest = offsets.max(), let height = stored.first?.image.height else { return 0 }
        return highest - lowest + height
    }

    /// La barra de desplazamiento, en columnas de la firma.
    func scrollbarColumns(imageWidth: Int) -> Int {
        let measured = imageWidth - scrollbarPixels
        guard measured > 0, signatureColumns > 0 else { return 0 }
        return Int((Double(scrollbarPixels * signatureColumns) / Double(measured)).rounded(.up))
    }

    /// La imagen final: todo lo guardado, montado por capas.
    func compose() -> CGImage? {
        for edge in [topEdge, bottomEdge].compactMap({ $0 }) where !stored.contains(where: { $0.offset == edge.offset }) {
            stored.append(edge)
        }
        topEdge = nil; bottomEdge = nil
        guard let first = stored.first else { return nil }
        let width = first.image.width
        var bars = fixedBars(height: first.image.height)
        var plan = ScrollStitcher.layout(offsets: stored.map(\.offset), clean: stored.map(\.clean),
                                         height: first.image.height, top: bars.top, bottom: bars.bottom)
        if !ScrollStitcher.coversEverything(plan) {
            bars = smallestBars(height: first.image.height)
            plan = ScrollStitcher.layout(offsets: stored.map(\.offset), clean: stored.map(\.clean),
                                         height: first.image.height, top: bars.top, bottom: bars.bottom)
        }
        var columns = ScrollStitcher.keptColumns(moves).map { pixelRange($0, imageWidth: width) } ?? 0..<width
        // Las imágenes en movimiento llevan la barra de desplazamiento en el borde derecho
        // de lo que se mueve. Si alguna entra en la imagen, esa franja se quita: si no,
        // saldría un trozo de barra en cada tramo.
        if stored.contains(where: { !$0.clean }) {
            let trim = min(scrollbarPixels, columns.count / 10)
            columns = columns.lowerBound..<(columns.upperBound - trim)
        }
        return ScrollStitcher.render(images: stored.map(\.image), plan: plan, xRange: columns)
    }

    /// De columnas de la firma a píxeles. La firma no mira el borde derecho (la barra):
    /// si el recorte llega al final, llega hasta el borde de verdad.
    private func pixelRange(_ kept: Range<Int>, imageWidth: Int) -> Range<Int> {
        let measured = imageWidth - scrollbarPixels
        let count = signatureColumns
        guard count > 0, measured > 0 else { return 0..<imageWidth }
        let lower = kept.lowerBound * measured / count
        let upper = kept.upperBound >= count ? imageWidth : (kept.upperBound * measured + count - 1) / count
        return max(0, lower)..<min(imageWidth, max(lower + 1, upper))
    }
}

/// El flujo de imágenes de la zona (ScreenCaptureKit), solo mientras dura la captura.
final class ZoneStream: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func start(rect: CGRect, screen: NSScreen, queue: DispatchQueue) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        // Fuera el marco y el aviso: son de OmniMac.
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        configuration.sourceRect = local
        configuration.width = Int(local.width * scale)
        configuration.height = Int(local.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 6
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { onFrame(image) }
    }
}

extension CGImage {
    /// Una copia en memoria propia (las del flujo son búferes que hay que devolver).
    func copied() -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return self }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? self
    }
}

/// Una captura con scroll en marcha. **Te desplazas tú**, a tu ritmo y tan rápido como
/// quieras: OmniMac no mueve nada, va recibiendo la zona a 30 imágenes por segundo, cose
/// lo que pasa por ella y para cuando pulsas «Listo» (o otra vez ⇧⌘8). Esc cancela.
@MainActor
final class ScrollingSession {
    let rect: CGRect
    let screen: NSScreen
    var onFinish: (() -> Void)?

    /// Tope: una página infinita (un muro de una red social) no tiene final.
    static let maxPixelHeight = 20_000

    private let tracker: ScrollTracker
    private var zone: ZoneStream?
    private var done = false
    private let status = ScrollingStatus()
    private var border: NSWindow?
    private var hud: NSPanel?
    private var monitors: [Any] = []

    init(rect: CGRect, screen: NSScreen) {
        self.rect = rect
        self.screen = screen
        tracker = ScrollTracker(scrollbarPixels: Int(24 * screen.backingScaleFactor))
    }

    func start() {
        showChrome()
        let status = self.status
        tracker.onProgress = { [weak self] pixels, lost in
            DispatchQueue.main.async {
                status.pixels = pixels
                status.lost = lost
                if pixels >= Self.maxPixelHeight { self?.finishNow() }
            }
        }
        let tracker = self.tracker
        let zone = ZoneStream { image in tracker.ingest(image) }
        self.zone = zone
        Task { @MainActor in
            do {
                try await zone.start(rect: rect, screen: screen, queue: tracker.queue)
            } catch {
                hideChrome()
                done = true
                Toast.show(L("No se pudo capturar la pantalla", "Couldn't capture the screen"), symbol: "exclamationmark.triangle.fill")
                onFinish?()
            }
        }
    }

    /// «Listo» u otra vez ⇧⌘8: se monta lo que haya.
    func finishNow() {
        guard !done else { return }
        done = true
        let tracker = self.tracker
        let zone = self.zone
        Task { @MainActor in
            await zone?.stop()
            // Lo que quede en la cola del rastreador, y después el montaje, ahí mismo.
            let result: (CGImage?, Bool) = await withCheckedContinuation { continuation in
                tracker.queue.async { continuation.resume(returning: (tracker.compose(), tracker.moves.isEmpty)) }
            }
            hideChrome()
            defer { onFinish?() }
            guard let image = result.0 else {
                Toast.show(L("No se pudo montar la captura", "Couldn't put the screenshot together"), symbol: "exclamationmark.triangle.fill")
                return
            }
            if result.1 {
                // Se copia lo que se ve, pero se dice: si no, parece que no ha funcionado.
                ScreenshotCapture.copy(image, symbol: "scroll", note: L("no te has desplazado: solo lo visible",
                                                                          "you didn't scroll: visible part only"))
            } else {
                ScreenshotCapture.copy(image, symbol: "scroll")
            }
        }
    }

    /// Esc: fuera, sin copiar nada.
    func cancel() {
        guard !done else { return }
        done = true
        let zone = self.zone
        Task { @MainActor in await zone?.stop() }
        hideChrome()
        Toast.show(L("Captura cancelada", "Capture cancelled"), symbol: "xmark.circle")
        onFinish?()
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

        // Cuándo te desplazas (para saber qué imágenes son «limpias») y Esc para
        // cancelar. Globales: la app de delante es la que se desplaza. Intro no: en un chat
        // enviaría el mensaje.
        let tracker = self.tracker
        if let wheel = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { _ in
            let now = Date()
            tracker.queue.async { tracker.lastScrollAt = now }
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
                    Text(L("Se ha perdido el hilo: vuelve un poco atrás", "Lost track: scroll back a little"))
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
