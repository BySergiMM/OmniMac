import AVFoundation
import AppKit

// Monta el vídeo de presentación a partir de clips grabados con `screencapture -v`:
// cada escena se recorta, se escala sobre un fondo degradado y lleva un título; hay
// una tarjeta de entrada y otra de cierre. Sin dependencias (AVFoundation + CoreGraphics).
//
// Uso: swift scripts/dev/video.swift <spec.json>
// El JSON describe tamaño, fps, tarjetas y escenas (ver docs/VIDEO.md y el ejemplo en
// scripts/dev/video-es.json). Coordenadas de recorte en píxeles del clip original.
struct Card: Decodable { let title: String; let subtitle: String; let seconds: Double; let icon: String? }
struct Scene: Decodable {
    let clip: String; let from: Double; let to: Double
    let crop: [Double]            // x, y, ancho, alto en píxeles del clip
    let title: String; let subtitle: String
    let width: Double?            // ancho del clip en el lienzo (por defecto 90 %)
    let y: Double?                // centro vertical del clip (0–1, por defecto 0.42)
}
struct Spec: Decodable { let width: Int; let height: Int; let fps: Int; let output: String; let intro: Card; let outro: Card; let scenes: [Scene]; let bitrate: Int? }   // bitrate en bits/s (10 Mb/s por defecto)

let args = CommandLine.arguments
guard args.count == 2, let data = FileManager.default.contents(atPath: args[1]), let spec = try? JSONDecoder().decode(Spec.self, from: data) else {
    print("uso: video.swift <spec.json>"); exit(1)
}
let W = spec.width, H = spec.height, fps = spec.fps
let vertical = H > W

// MARK: lienzo
func canvas() -> CGContext {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}
func background(_ ctx: CGContext) {
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let colors = [CGColor(red: 0.16, green: 0.145, blue: 0.376, alpha: 1), CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: Double(W) * 0.3, y: Double(H) * 1.15), startRadius: 0, endCenter: CGPoint(x: Double(W) * 0.3, y: Double(H) * 1.15), endRadius: Double(max(W, H)) * 0.95, options: [])
}
/// Dibuja texto centrado con el borde superior del bloque en `top` (coordenadas de
/// CoreGraphics, origen abajo). Devuelve la altura real del bloque, que puede ocupar
/// varias líneas, para colocar debajo lo siguiente sin solaparse.
@discardableResult
func text(_ ctx: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat, alpha: CGFloat = 1, maxWidth: CGFloat? = nil) -> CGFloat {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color.withAlphaComponent(alpha), .paragraphStyle: paragraph, .kern: -size * 0.02]
    let width = maxWidth ?? CGFloat(W) * 0.86
    let bounding = (string as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes)
    let height = ceil(bounding.height)
    (string as NSString).draw(with: CGRect(x: (CGFloat(W) - width) / 2, y: top - height, width: width, height: height), options: [.usesLineFragmentOrigin], attributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return height
}
func rounded(_ ctx: CGContext, _ image: CGImage, in rect: CGRect, radius: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path); ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
}
func loadIcon(_ path: String?) -> CGImage? {
    guard let path, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: escritor
let output = URL(fileURLWithPath: spec.output)
try? FileManager.default.removeItem(at: output)
let writer = try! AVAssetWriter(outputURL: output, fileType: .mp4)
let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                               AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: spec.bitrate ?? 10_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: fps]]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
var frameIndex = 0
func emit(_ ctx: CGContext) {
    guard let pool = adaptor.pixelBufferPool else { fatalError("sin pool") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { return }
    CVPixelBufferLockBaseAddress(buffer, [])
    let dst = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    dst.draw(ctx.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    while !input.isReadyForMoreMediaData { usleep(2000) }
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps)))
    frameIndex += 1
}
func ease(_ t: Double) -> CGFloat { CGFloat(t < 0 ? 0 : t > 1 ? 1 : (1 - cos(t * .pi)) / 2) }

// MARK: tarjetas
func card(_ c: Card, isOutro: Bool) {
    let frames = Int(c.seconds * Double(fps))
    let icon = loadIcon(c.icon)
    for i in 0..<frames {
        let ctx = canvas(); background(ctx)
        let t = Double(i) / Double(fps)
        let fadeIn = ease(t / 0.5), fadeOut = isOutro ? 1 : ease((c.seconds - t) / 0.4)
        let a = min(fadeIn, fadeOut)
        let titleSize: CGFloat = vertical ? 78 : 96, subSize: CGFloat = vertical ? 36 : 40
        // El bloque (icono + título + subtítulo) se centra en vertical según su altura real.
        let attributesT: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: titleSize, weight: .bold)]
        let attributesS: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: subSize, weight: .medium)]
        let width = CGFloat(W) * 0.86
        let hT = ceil((c.title as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributesT).height)
        let hS = ceil((c.subtitle as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributesS).height)
        let side: CGFloat = icon == nil ? 0 : (vertical ? 240 : 200)
        let gapIcon: CGFloat = icon == nil ? 0 : 44, gapText: CGFloat = 18
        let total = side + gapIcon + hT + gapText + hS
        var top = CGFloat(H) / 2 + total / 2
        if let icon {
            rounded(ctx, icon, in: CGRect(x: (CGFloat(W) - side) / 2, y: top - side, width: side, height: side), radius: side * 0.22, alpha: a)
            top -= side + gapIcon
        }
        top -= text(ctx, c.title, size: titleSize, weight: .bold, color: .white, top: top, alpha: a) + gapText
        text(ctx, c.subtitle, size: subSize, weight: .medium, color: NSColor(white: 0.78, alpha: 1), top: top, alpha: a)
        emit(ctx)
    }
}

// MARK: escenas
func scene(_ s: Scene) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: s.clip))
    guard let track = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { print("clip ilegible: \(s.clip)"); return }
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(out); reader.timeRange = CMTimeRange(start: CMTime(seconds: s.from, preferredTimescale: 600), end: CMTime(seconds: s.to, preferredTimescale: 600)); reader.startReading()
    let total = Int((s.to - s.from) * Double(fps))
    var current: CGImage? = nil
    var nextSample = out.copyNextSampleBuffer()
    let crop = CGRect(x: s.crop[0], y: s.crop[1], width: s.crop[2], height: s.crop[3])
    var targetWidth = CGFloat(W) * CGFloat(s.width ?? 0.9)
    var targetHeight = targetWidth * crop.height / crop.width
    // El clip nunca invade la banda del título: en horizontal como mucho el 60 % de la
    // altura; en vertical, el 50 % (los recortes altos se reducen de ancho).
    let maxHeight = CGFloat(H) * (vertical ? 0.50 : 0.60)
    if targetHeight > maxHeight { targetWidth *= maxHeight / targetHeight; targetHeight = maxHeight }
    let centerY = CGFloat(H) * CGFloat(s.y ?? (vertical ? 0.60 : 0.44))
    let rect = CGRect(x: (CGFloat(W) - targetWidth) / 2, y: centerY - targetHeight / 2, width: targetWidth, height: targetHeight)
    for i in 0..<total {
        let t = s.from + Double(i) / Double(fps)
        while let sample = nextSample, CMSampleBufferGetPresentationTimeStamp(sample).seconds <= t + 0.001 {
            if let pb = CMSampleBufferGetImageBuffer(sample) {
                CVPixelBufferLockBaseAddress(pb, .readOnly)
                if let c = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let img = c.makeImage() {
                    current = img.cropping(to: crop)
                }
                CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            }
            nextSample = out.copyNextSampleBuffer()
        }
        let ctx = canvas(); background(ctx)
        let local = Double(i) / Double(fps), remaining = Double(total - i) / Double(fps)
        let a = min(ease(local / 0.35), ease(remaining / 0.3))
        if let current { rounded(ctx, current, in: rect, radius: vertical ? 22 : 18, alpha: a) }
        let titleSize: CGFloat = vertical ? 56 : 58, subSize: CGFloat = vertical ? 32 : 30
        // Título bajo el clip (vertical) o en la banda inferior (horizontal); el subtítulo
        // va justo debajo del título, a la distancia que marque su altura real.
        var top = vertical ? rect.minY - 70 : CGFloat(H) * 0.20 + titleSize * 1.2
        top -= text(ctx, s.title, size: titleSize, weight: .bold, color: .white, top: top, alpha: a * ease((local - 0.15) / 0.35)) + 14
        text(ctx, s.subtitle, size: subSize, weight: .medium, color: NSColor(white: 0.78, alpha: 1), top: top, alpha: a * ease((local - 0.3) / 0.35))
        emit(ctx)
    }
    reader.cancelReading()
}

card(spec.intro, isOutro: false)
for s in spec.scenes { scene(s) }
card(spec.outro, isOutro: true)
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
let size = (try? FileManager.default.attributesOfItem(atPath: spec.output)[.size] as? Int) ?? 0
print("\(spec.output): \(frameIndex) fotogramas, \(Double(frameIndex) / Double(fps)) s, \(size / 1_000_000) MB, estado \(writer.status.rawValue)\(writer.error.map { " · \($0)" } ?? "")")
