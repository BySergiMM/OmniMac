import AppKit

// Fondo oscuro para grabar vídeo: una ventana sin bordes que cubre la pantalla por
// debajo de las demás ventanas (justo encima de los iconos del escritorio), con el
// mismo degradado que el hero de la web. Se cierra con SIGTERM / kill.
// Uso: swift scripts/dev/backdrop.swift &
final class Backdrop: NSView {
    override func draw(_ rect: NSRect) {
        NSColor.black.setFill(); rect.fill()
        let gradient = NSGradient(colors: [NSColor(red: 0.16, green: 0.145, blue: 0.376, alpha: 1), NSColor.black])!
        gradient.draw(in: bounds, relativeCenterPosition: NSPoint(x: -0.4, y: 1.2))
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.screens.first else { exit(1) }
let menuBar = screen.frame.height - screen.visibleFrame.maxY
let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - menuBar)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .normal   // por encima de los widgets del escritorio; las ventanas que actives después quedan encima
window.isOpaque = true
window.hasShadow = false
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.contentView = Backdrop(frame: frame)
window.orderFrontRegardless()
app.run()
