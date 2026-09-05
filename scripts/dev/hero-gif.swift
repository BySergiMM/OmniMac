import AppKit
import ImageIO
import UniformTypeIdentifiers

// Monta un GIF animado a partir de una carpeta de fotogramas PNG (capturas de Chrome sin
// ventana del hero de la web con ?demo=1), recortando una zona y escalándola.
// Sin dependencias: ImageIO escribe el GIF (256 colores por fotograma, suficiente para
// una interfaz oscura).
//
// Uso: swift scripts/dev/hero-gif.swift <carpeta> <x> <y> <ancho> <alto> <anchoSalida> <segundosPorFotograma> <salida.gif>
//   x, y, ancho y alto son píxeles del PNG de origen (a 2x si la captura se hizo a 2x).
//   El último fotograma se mantiene 12 veces más para que el bucle "respire".
let a = CommandLine.arguments
guard a.count == 9, let x = Int(a[2]), let y = Int(a[3]), let w = Int(a[4]), let h = Int(a[5]),
      let targetWidth = Int(a[6]), let delay = Double(a[7]) else {
    print("uso: hero-gif.swift <carpeta> <x> <y> <ancho> <alto> <anchoSalida> <segundos> <salida.gif>"); exit(1)
}
let dir = a[1], out = a[8]
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.hasSuffix(".png") }.sorted() ?? []
guard !files.isEmpty else { print("sin fotogramas en \(dir)"); exit(1) }
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.gif.identifier as CFString, files.count, nil) else {
    print("no se pudo crear \(out)"); exit(1)
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let targetHeight = Int((Double(h) * Double(targetWidth) / Double(w)).rounded())
var written = 0
for (index, file) in files.enumerated() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: dir + "/" + file) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)),
          let context = CGContext(data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("fotograma ilegible: \(file)"); continue
    }
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    guard let scaled = context.makeImage() else { continue }
    let frameDelay = index == files.count - 1 ? delay * 12 : delay
    let properties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay,
                                                                        kCGImagePropertyGIFUnclampedDelayTime: frameDelay]]
    CGImageDestinationAddImage(dest, scaled, properties as CFDictionary)
    written += 1
}
guard CGImageDestinationFinalize(dest) else { print("no se pudo escribir el GIF"); exit(1) }
let size = (try? FileManager.default.attributesOfItem(atPath: out)[.size] as? Int) ?? 0
print("\(out): \(written) fotogramas, \(targetWidth)×\(targetHeight), \(size / 1024) KB")
