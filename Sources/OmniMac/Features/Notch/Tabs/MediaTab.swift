import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña de música

struct MediaTab: View {
    @ObservedObject var media: MediaBridge
    @ObservedObject var hover: HoverState
    @State private var preferredPlayer = MusicPlayer.preferred

    var body: some View {
        if preferredPlayer?.isInstalled != true {
            PlayerPicker { player in
                MusicPlayer.preferred = player
                preferredPlayer = player
            }
        } else if media.launching {
            launchingView
        } else if media.nowPlaying == nil, let player = preferredPlayer, !player.isRunning {
            playFromScratch(player)
        } else {
            playerBody
        }
    }

    @ViewBuilder
    private var playerBody: some View {
        if let info = media.nowPlaying {
            HStack(alignment: .center, spacing: 18) {
                artwork(for: info)

                VStack(alignment: .leading, spacing: 0) {
                    Text(info.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 4)

                    TrackProgress(position: info.position, duration: info.duration) { seconds in
                        media.seek(to: seconds)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        HoverCircleButton(symbol: "backward.fill", iconSize: 18, diameter: 34, hover: hover) {
                            media.previousTrack()
                        }
                        HoverCircleButton(symbol: info.isPlaying ? "pause.fill" : "play.fill",
                                          iconSize: 24, diameter: 44, hover: hover) {
                            media.playPause()
                        }
                        HoverCircleButton(symbol: "forward.fill", iconSize: 18, diameter: 34, hover: hover) {
                            media.nextTrack()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.07))
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nada sonando")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Pon música en Música o Spotify\ny contrólala desde aquí.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Mientras se abre el reproductor asignado.
    private var launchingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Abriendo \(preferredPlayer?.displayName ?? "el reproductor")…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    /// El reproductor asignado está cerrado: un play grande lo lanza y empieza a sonar.
    private func playFromScratch(_ player: MusicPlayer) -> some View {
        HStack(spacing: 16) {
            if let icon = player.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(player.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Cerrada · dale al play y empieza a sonar")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Button {
                    MusicPlayer.preferred = nil
                    preferredPlayer = nil
                } label: {
                    Text("Cambiar de app")
                        .font(.system(size: 10.5))
                        .underline()
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button {
                media.launchAndPlay(player)
            } label: {
                ZStack {
                    Circle().fill(.white)
                        .frame(width: 46, height: 46)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: 1)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reproducir en \(player.displayName)")
        }
        .padding(.horizontal, 6)
    }

    private var artworkImage: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Brand.gradient.opacity(0.55))
                    Image(systemName: "music.note")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    /// Carátula grande con la insignia de la app que reproduce en la esquina.
    private func artwork(for info: NowPlayingInfo) -> some View {
        let side: CGFloat = 104
        let playing = info.isPlaying
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                // Resplandor de la propia carátula por detrás ("iluminado" al sonar).
                // Siempre presente y solo se anima su opacidad/escala: insertarlo y
                // quitarlo con una transición daba un "pop" nada fluido.
                if let artwork = media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .blur(radius: 22)
                        .opacity(playing ? 0.62 : 0)
                        .scaleEffect(playing ? 1.06 : 0.92)
                        .offset(y: 8)
                }
                artworkImage
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        // En pausa: capa gris por encima.
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(white: 0.5).opacity(playing ? 0 : 0.55))
                    )
                    .saturation(playing ? 1 : 0.55)
                    .scaleEffect(playing ? 1 : 0.94)
                    .shadow(color: .black.opacity(playing ? 0.55 : 0), radius: 10, y: 6)
            }
            // Asimétrica: se enciende ágil y se apaga despacio (el resplandor se va
            // suave). Curvas de easing, que encadenan bien si pulsas varias veces.
            .animation(playing ? .easeOut(duration: 0.6) : .easeInOut(duration: 1.2), value: playing)

            if let icon = MusicPlayer(rawValue: info.bundleID)?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
                    .offset(x: 6, y: 6)
            }
        }
        .frame(width: side, height: side)
    }
}

/// Primera vez: el usuario asigna su app de música (solo se ofrecen las instaladas).
struct PlayerPicker: View {
    let onSelect: (MusicPlayer) -> Void
    private let players = MusicPlayer.installed

    var body: some View {
        VStack(spacing: 10) {
            Text("¿Con qué app escuchas música?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if players.isEmpty {
                Text("No encuentro Spotify ni Apple Music en este Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                HStack(spacing: 12) {
                    ForEach(players) { player in
                        Button {
                            onSelect(player)
                        } label: {
                            VStack(spacing: 6) {
                                if let icon = player.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 42, height: 42)
                                }
                                Text(player.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("La podrás cambiar cuando quieras en Ajustes → Notch")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Barra de progreso de la canción con tiempos. Arrastra para saltar a cualquier
/// punto, como en el reproductor real; un clic suelto no salta (distancia mínima).
struct TrackProgress: View {
    let position: Int
    let duration: Int
    let onSeek: (Int) -> Void

    @State private var dragFraction: Double?

    private var isDragging: Bool { dragFraction != nil }

    private var displayedFraction: Double {
        if let dragFraction { return dragFraction }
        return duration > 0 ? min(1, Double(position) / Double(duration)) : 0
    }

    private var displayedPosition: Int {
        if let dragFraction { return Int(dragFraction * Double(duration)) }
        return position
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let barHeight: CGFloat = isDragging ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(.white.opacity(isDragging ? 1 : 0.9))
                        .frame(width: max(3, geo.size.width * displayedFraction), height: barHeight)
                    if isDragging {
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .offset(x: geo.size.width * displayedFraction - 5.5)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragFraction = min(1, max(0, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            guard duration > 0 else {
                                dragFraction = nil
                                return
                            }
                            let fraction = min(1, max(0, value.location.x / geo.size.width))
                            onSeek(Int(fraction * Double(duration)))
                            // la dejamos donde la soltaste hasta que el reproductor confirme
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                dragFraction = nil
                            }
                        }
                )
            }
            .frame(height: 14)
            // Transición corta: suaviza el salto del poll sin mantener vivo el
            // bucle de fotogramas (una animación larga tendría el CADisplayLink
            // renderizando casi todo el tiempo).
            .animation(isDragging ? nil : .easeOut(duration: 0.35), value: displayedFraction)

            HStack {
                Text(Self.time(displayedPosition))
                Spacer()
                Text(Self.time(duration))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(isDragging ? 0.85 : 0.5))
        }
    }

    private static func time(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
