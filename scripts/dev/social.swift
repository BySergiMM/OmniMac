import AppKit

// Tarjeta social de 1280×640: la que enseña GitHub al compartir el repositorio y la
// que sale al pegar el enlace de la web en LinkedIn, X o WhatsApp.
//
// Se hacía a mano recortando el hero de la web, y por eso se quedó en español y
// anunciando siete módulos cuando ya eran once. Ahora se genera:
//
//   swift scripts/dev/social.swift es docs/site/img/social-preview.png
//   swift scripts/dev/social.swift en docs/site/img/en/social-preview.png
//
// Al subir de versión hay que volver a lanzarla (está en docs/RELEASE.md).

let args = CommandLine.arguments
guard args.count == 3 else {
    print("uso: social.swift <es|en> <salida.png>")
    exit(1)
}
let spanish = args[1].lowercased().hasPrefix("es")
let outputPath = args[2]

let W = 1280, H = 640

// MARK: - Textos

let eyebrow  = spanish ? "MACOS · GRATIS · CÓDIGO ABIERTO" : "MACOS · FREE · OPEN SOURCE"
let title    = spanish ? "Todo lo que le falta\na tu Mac." : "Everything your Mac\nis missing."
let subtitle = spanish ? "Once utilidades en una sola app de la barra de menús."
                       : "Eleven utilities in one menu bar app."
// Las tres cifras que de verdad convencen, y que son las que hay que revisar al
// cambiar de versión.
let stats: [String] = spanish ? ["0,017 % de CPU en reposo", "33–37 MB", "16 MB en disco"]
                              : ["0.017% CPU at idle", "33–37 MB", "16 MB on disk"]

// MARK: - Lienzo

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.interpolationQuality = .high

// Mismo degradado que el fondo de los vídeos y el hero de la web, para que las tres
// cosas se reconozcan como la misma marca.
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.24, green: 0.20, blue: 0.56, alpha: 1),
                                   CGColor(red: 0.055, green: 0.045, blue: 0.13, alpha: 1),
                                   CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFArray,
                          locations: [0, 0.38, 1])!
// El brillo se concentra arriba a la izquierda, detrás del icono y del titular, y
// el resto cae casi a negro: así el texto blanco tiene contraste de verdad y la
// captura del notch no compite con el fondo.
ctx.drawRadialGradient(gradient,
                       startCenter: CGPoint(x: Double(W) * 0.06, y: Double(H) * 1.06), startRadius: 0,
                       endCenter: CGPoint(x: Double(W) * 0.06, y: Double(H) * 1.06), endRadius: 1480,
                       options: [])

let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns

/// Dibuja texto alineado a la izquierda con el borde **superior** en `top`
/// (coordenadas de CoreGraphics, origen abajo). Devuelve la altura ocupada, para
/// encadenar lo siguiente sin solapar.
@discardableResult
func draw(_ string: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, tracking: CGFloat = 0, maxWidth: CGFloat = 640, lineHeight: CGFloat? = nil) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    if let lineHeight { paragraph.maximumLineHeight = lineHeight; paragraph.minimumLineHeight = lineHeight }
    var attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    if tracking != 0 { attributes[.kern] = tracking }
    let bounding = (string as NSString).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin], attributes: attributes)
    let height = ceil(bounding.height)
    (string as NSString).draw(with: CGRect(x: x, y: top - height, width: maxWidth, height: height),
                              options: [.usesLineFragmentOrigin], attributes: attributes)
    return height
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - Columna izquierda

let left: CGFloat = 76
var cursor: CGFloat = CGFloat(H) - 78      // vamos bajando desde arriba

if let icon = loadImage("docs/site/img/icon-512.png") {
    let side: CGFloat = 84
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.draw(icon, in: CGRect(x: left, y: cursor - side, width: side, height: side))
    ctx.restoreGState()
    cursor -= side + 34
}

cursor -= draw(eyebrow, x: left, top: cursor, size: 15, weight: .bold,
               color: NSColor(red: 0.72, green: 0.70, blue: 1.0, alpha: 1), tracking: 1.7) + 18

// El titular es lo único que se lee cuando la tarjeta sale pequeña en un feed.
cursor -= draw(title, x: left, top: cursor, size: 58, weight: .bold,
               color: .white, tracking: -1.2, lineHeight: 64) + 20

cursor -= draw(subtitle, x: left, top: cursor, size: 24, weight: .regular,
               color: NSColor(white: 0.80, alpha: 1), maxWidth: 600, lineHeight: 32) + 34

// MARK: - Las cifras, en pastillas

var pillX = left
let pillHeight: CGFloat = 38
for stat in stats {
    let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    let width = ceil((stat as NSString).size(withAttributes: [.font: font]).width) + 30
    let rect = CGRect(x: pillX, y: cursor - pillHeight, width: width, height: pillHeight)
    let path = CGPath(roundedRect: rect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.09))
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(1)
    ctx.strokePath()
    (stat as NSString).draw(at: CGPoint(x: pillX + 15, y: cursor - pillHeight + 11),
                            withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.93, alpha: 1)])
    pillX += width + 10
}

// MARK: - El notch, a la derecha

// La captura del notch es lo que hace entender de un vistazo qué es esto. Se sangra
// por el borde derecho a propósito: da sensación de que hay más.
let notchPath = spanish ? "docs/site/img/notch-media.png" : "docs/site/img/en/notch-media.png"
if let notch = loadImage(notchPath) {
    let width: CGFloat = 596
    let height = width * CGFloat(notch.height) / CGFloat(notch.width)
    let rect = CGRect(x: CGFloat(W) - width - 56, y: (CGFloat(H) - height) / 2, width: width, height: height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -10, height: -16), blur: 44,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
    let rounded = CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.addPath(rounded)
    ctx.clip()
    ctx.draw(notch, in: rect)
    ctx.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()

// MARK: - Guardar

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL,
                                                        "public.png" as CFString, 1, nil) else {
    print("no se pudo escribir \(outputPath)")
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size]) as? Int ?? 0
print("\(outputPath): \(W)×\(H), \(bytes / 1024) KB")
