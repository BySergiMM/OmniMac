import AppKit
import SwiftUI

/// Ajusta ventanas arrastrándolas a los bordes o esquinas de la pantalla, como
/// Rectangle: mientras arrastras, una "huella" enseña dónde quedará la ventana; al
/// soltar, se coloca. Solo trabaja mientras hay un arrastre en curso; con el ratón
/// quieto no consume nada.
final class SnapDragMonitor {
    enum Zone: Equatable {
        case leftHalf, rightHalf, maximize, topLeft, topRight, bottomLeft, bottomRight

        func rect(in v: CGRect) -> CGRect {
            switch self {
            case .leftHalf:    CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
            case .rightHalf:   CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
            case .maximize:    v
            case .topLeft:     CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
            case .topRight:    CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
            case .bottomLeft:  CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
            case .bottomRight: CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
            }
        }

        /// Zona según dónde esté el cursor respecto al borde de la pantalla
        /// (coordenadas de Cocoa, origen abajo-izquierda).
        static func at(_ p: CGPoint, in f: CGRect) -> Zone? {
            let edge: CGFloat = 5
            let corner: CGFloat = 90
            let left = p.x <= f.minX + edge
            let right = p.x >= f.maxX - edge
            let top = p.y >= f.maxY - edge
            let bottom = p.y <= f.minY + edge
            if top {
                if p.x < f.minX + corner { return .topLeft }
                if p.x > f.maxX - corner { return .topRight }
                return .maximize
            }
            if left {
                if p.y > f.maxY - corner { return .topLeft }
                if p.y < f.minY + corner { return .bottomLeft }
                return .leftHalf
            }
            if right {
                if p.y > f.maxY - corner { return .topRight }
                if p.y < f.minY + corner { return .bottomRight }
                return .rightHalf
            }
            if bottom {
                if p.x < f.minX + corner { return .bottomLeft }
                if p.x > f.maxX - corner { return .bottomRight }
            }
            return nil
        }
    }

    private struct Drag {
        let window: AXUIElement
        let startWindowPosition: CGPoint   // coordenadas de Accesibilidad (y hacia abajo)
        let startMouse: CGPoint            // coordenadas de Cocoa (y hacia arriba)
        var confirmed = false
        var lastCheck: TimeInterval
        var zone: Zone? = nil
        var screen: NSScreen? = nil
    }

    private let focusedWindow: () -> AXUIElement?
    private let apply: (AXUIElement, CGRect) -> Void
    private var monitors: [Any] = []
    private var drag: Drag?
    /// El arrastre actual no es de una ventana (texto, iconos…): ignorar hasta soltar.
    private var ignoringCurrentDrag = false
    private let footprint = FootprintWindow()

    init(focusedWindow: @escaping () -> AXUIElement?, apply: @escaping (AXUIElement, CGRect) -> Void) {
        self.focusedWindow = focusedWindow
        self.apply = apply
    }

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            self?.dragged()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            self?.released()
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        drag = nil
        ignoringCurrentDrag = false
        footprint.hide()
    }

    private func dragged() {
        if ignoringCurrentDrag { return }
        let mouse = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime

        guard var d = drag else {
            // Empieza un arrastre: apuntamos la ventana activa y dónde estaba.
            guard Permissions.hasAccessibility,
                  let window = focusedWindow(),
                  let position = AX.point(window, kAXPositionAttribute as String) else {
                ignoringCurrentDrag = true
                return
            }
            drag = Drag(window: window, startWindowPosition: position, startMouse: mouse, lastCheck: now)
            return
        }

        if !d.confirmed {
            // Cada 60 ms comprobamos si la ventana se mueve con el ratón: si no lo hace
            // tras 80 px, es otra cosa (seleccionar texto, arrastrar un archivo…).
            guard now - d.lastCheck > 0.06 else { return }
            d.lastCheck = now
            let dx = mouse.x - d.startMouse.x
            let dy = mouse.y - d.startMouse.y
            let moved = hypot(dx, dy)
            if moved < 10 {
                drag = d
                return
            }
            let position = AX.point(d.window, kAXPositionAttribute as String) ?? d.startWindowPosition
            let wdx = position.x - d.startWindowPosition.x
            let wdy = -(position.y - d.startWindowPosition.y)
            if abs(wdx - dx) < 8 && abs(wdy - dy) < 8 {
                d.confirmed = true
            } else if moved > 80 {
                drag = nil
                ignoringCurrentDrag = true
                return
            } else {
                drag = d
                return
            }
        }

        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let zone = screen.map { Zone.at(mouse, in: $0.frame) } ?? nil
        if zone != d.zone || screen != d.screen {
            d.zone = zone
            d.screen = screen
            if let zone, let screen {
                footprint.show(zone.rect(in: screen.visibleFrame))
            } else {
                footprint.hide()
            }
        }
        drag = d
    }

    private func released() {
        defer {
            drag = nil
            ignoringCurrentDrag = false
            footprint.hide()
        }
        guard let d = drag, d.confirmed, let zone = d.zone, let screen = d.screen else { return }
        let rect = zone.rect(in: screen.visibleFrame)
        let window = d.window
        let apply = self.apply
        // La app remata su propio arrastre primero; después colocamos nosotros.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            apply(window, rect)
        }
    }
}

/// La "huella" translúcida que enseña dónde quedará la ventana.
final class FootprintWindow {
    private let window: NSWindow
    private let box = NSView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        window.level = .floating
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 2
        box.layer?.backgroundColor = NSColor(Brand.accent).withAlphaComponent(0.16).cgColor
        box.layer?.borderColor = NSColor(Brand.accent).withAlphaComponent(0.9).cgColor
        window.contentView = box
    }

    func show(_ rect: CGRect) {
        window.setFrame(rect.insetBy(dx: 4, dy: 4), display: true)
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        if window.isVisible { window.orderOut(nil) }
    }
}
