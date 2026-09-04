import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña sonido (salida + volumen por app)

struct SoundTab: View {
    @ObservedObject var sound: SoundFeature
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(sound.outputName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if sound.outputDevices.count > 1 {
                    Button {
                        sound.cycleOutput()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Siguiente salida")
                }
                Spacer(minLength: 8)
                VolumeBar(value: sound.outputVolume, accent: true) { sound.outputVolume = $0 }
                    .frame(width: 110)
                Text("\(Int(sound.outputVolume * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, alignment: .trailing)
            }

            if mixer.apps.isEmpty {
                VStack(spacing: 4) {
                    Text("Ninguna app está sonando")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Cuando alguna reproduzca audio podrás ponerle aquí su propio volumen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(mixer.apps) { app in
                            HStack(spacing: 8) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: 18, height: 18)
                                }
                                Text(app.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(app.isPlaying ? 1 : 0.55))
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                                VolumeBar(value: app.volume) { mixer.setVolume($0, for: app) }
                                Text("\(Int(app.volume * 100))%")
                                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            sound.refresh()
            mixer.beginWatching()
        }
        .onDisappear { mixer.endWatching() }
    }
}

/// Barra de volumen arrastrable (el `Slider` del sistema no responde bien en un
/// panel sin activación; esta funciona como la barra de progreso de la música).
struct VolumeBar: View {
    let value: Float
    var accent = false
    let onChange: (Float) -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let height: CGFloat = dragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: height)
                Capsule()
                    .fill(.white.opacity(accent || dragging ? 1 : 0.85))
                    .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, value)))), height: height)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        onChange(Float(min(1, max(0, drag.location.x / geo.size.width))))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 16)
    }
}
