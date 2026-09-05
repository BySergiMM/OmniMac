import AVFoundation
import AppKit

// Extrae un fotograma de un vídeo a PNG. Uso: swift scripts/dev/frame.swift <vídeo> <segundos> <salida.png>
let a = CommandLine.arguments
guard a.count == 4, let seconds = Double(a[2]) else { print("uso: frame.swift <vídeo> <segundos> <salida.png>"); exit(1) }
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
let rep = NSBitmapImageRep(cgImage: image)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
print("\(a[3]): \(image.width)×\(image.height)")
