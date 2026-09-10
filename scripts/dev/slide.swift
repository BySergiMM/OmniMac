import AppKit

// Una diapositiva 1920×1080 con el fondo de la marca: captura arriba, rótulo debajo.
// Es lo mismo que hace `video.swift` con cada escena, pero a partir de un PNG suelto,
// para poder ilustrar algo que no da un vídeo decente (un aviso, un diálogo).
//
//   swift scripts/dev/slide.swift <captura.png> "Título" "Subtítulo" <salida.png>

let a = CommandLine.arguments
guard a.count == 5 else { print("uso: slide.swift <captura.png> <título> <subtítulo> <salida.png>"); exit(1) }
let (shotPath, title, subtitle, outPath) = (a[1], a[2], a[3], a[4])

let W = 1920, H = 1080
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.interpolationQuality = .high

ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.16, green: 0.145, blue: 0.376, alpha: 1),
                                   CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawRadialGradient(gradient,
                       startCenter: CGPoint(x: Double(W) * 0.3, y: Double(H) * 1.15), startRadius: 0,
                       endCenter: CGPoint(x: Double(W) * 0.3, y: Double(H) * 1.15), endRadius: Double(W) * 0.95,
                       options: [])

let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns

@discardableResult
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat) -> CGFloat {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color, .paragraphStyle: p,
                                                .kern: -size * 0.02]
    let width = CGFloat(W) * 0.86
    let h = ceil((s as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                              options: [.usesLineFragmentOrigin], attributes: attrs).height)
    (s as NSString).draw(with: CGRect(x: (CGFloat(W) - width) / 2, y: top - h, width: width, height: h),
                         options: [.usesLineFragmentOrigin], attributes: attrs)
    return h
}

// La captura, con el mismo tope de altura que las escenas del vídeo (60 %) para que
// nunca invada la banda del rótulo.
if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: shotPath) as CFURL, nil),
   let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) {
    var w = CGFloat(W) * 0.72
    var h = w * CGFloat(shot.height) / CGFloat(shot.width)
    let maxH = CGFloat(H) * 0.60
    if h > maxH { w *= maxH / h; h = maxH }
    let rect = CGRect(x: (CGFloat(W) - w) / 2, y: CGFloat(H) * 0.60 - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.clip()
    ctx.draw(shot, in: rect)
    ctx.restoreGState()
}

var top = CGFloat(H) * 0.20 + 58 * 1.2
top -= text(title, size: 58, weight: .bold, color: .white, top: top) + 14
text(subtitle, size: 30, weight: .medium, color: NSColor(white: 0.78, alpha: 1), top: top)

NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil) else {
    print("no se pudo escribir \(outPath)"); exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("\(outPath): \(W)×\(H)")
