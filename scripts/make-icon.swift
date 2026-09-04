#!/usr/bin/swift
// Genera Resources/AppIcon.icns con el logo de OmniMac.
// Ejecutar desde la raíz del repo:  swift scripts/make-icon.swift
import AppKit

func sparkle(center c: NSPoint, radius r: CGFloat) -> NSBezierPath {
    let k = r * 0.18
    let path = NSBezierPath()
    path.move(to: NSPoint(x: c.x, y: c.y + r))
    path.curve(to: NSPoint(x: c.x + r, y: c.y),
               controlPoint1: NSPoint(x: c.x + k, y: c.y + k),
               controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
    path.curve(to: NSPoint(x: c.x, y: c.y - r),
               controlPoint1: NSPoint(x: c.x + k, y: c.y - k),
               controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
    path.curve(to: NSPoint(x: c.x - r, y: c.y),
               controlPoint1: NSPoint(x: c.x - k, y: c.y - k),
               controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
    path.curve(to: NSPoint(x: c.x, y: c.y + r),
               controlPoint1: NSPoint(x: c.x - k, y: c.y + k),
               controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
    path.close()
    return path
}

func drawIcon(_ s: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.098                       // margen estándar de iconos macOS
    let icon = full.insetBy(dx: inset, dy: inset)
    let radius = icon.width * 0.225
    let squircle = NSBezierPath(roundedRect: icon, xRadius: radius, yRadius: radius)

    // Fondo: degradado violeta OmniMac
    let bottom = NSColor(calibratedRed: 0.09, green: 0.05, blue: 0.26, alpha: 1)
    let top = NSColor(calibratedRed: 0.45, green: 0.30, blue: 1.00, alpha: 1)
    NSGradient(colors: [bottom, top])!.draw(in: squircle, angle: 65)

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()

    // Notch negro arriba, centrado
    let notchW = icon.width * 0.40
    let notchH = icon.height * 0.115
    let x0 = icon.midX - notchW / 2
    let x1 = icon.midX + notchW / 2
    let yTop = icon.maxY
    let yBottom = yTop - notchH
    let r = notchH * 0.42
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: x0, y: yTop))
    notch.line(to: NSPoint(x: x1, y: yTop))
    notch.appendArc(from: NSPoint(x: x1, y: yBottom), to: NSPoint(x: x0, y: yBottom), radius: r)
    notch.appendArc(from: NSPoint(x: x0, y: yBottom), to: NSPoint(x: x0, y: yTop), radius: r)
    notch.close()
    NSColor.black.setFill()
    notch.fill()

    // Chispa blanca con brillo
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedWhite: 1, alpha: 0.55)
    glow.shadowBlurRadius = s * 0.035
    glow.set()
    NSColor.white.setFill()
    let center = NSPoint(x: icon.midX, y: icon.midY - icon.height * 0.05)
    sparkle(center: center, radius: icon.width * 0.24).fill()
    sparkle(center: NSPoint(x: center.x + icon.width * 0.205, y: center.y + icon.height * 0.215),
            radius: icon.width * 0.075).fill()

    NSGraphicsContext.current?.restoreGraphicsState()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(CGFloat(px))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    try! render(px).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "✅ Resources/AppIcon.icns generado" : "❌ iconutil falló")
