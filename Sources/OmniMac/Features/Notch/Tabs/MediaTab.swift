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

                    TrackProgress(position: info.position, duration: info.duration, isPlaying: info.isPlaying) { seconds in
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
                    Text(L("Nada sonando", "Nothing playing"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(L("Pon música en Música o Spotify\ny contrólala desde aquí.", "Play something in Music or Spotify\nand control it from here."))
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
            Text(L("Abriendo \(preferredPlayer?.displayName ?? "el reproductor")…", "Opening \(preferredPlayer?.displayName ?? "the player")…"))
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
                Text(L("Cerrada · dale al play y empieza a sonar", "Closed · press play and it starts"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Button {
                    MusicPlayer.preferred = nil
                    preferredPlayer = nil
                } label: {
                    Text(L("Cambiar de app", "Switch app"))
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
            .help(L("Reproducir en \(player.displayName)", "Play in \(player.displayName)"))
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
            Text(L("¿Con qué app escuchas música?", "Which app do you listen to music with?"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if players.isEmpty {
                Text(L("No encuentro Spotify ni Apple Music en este Mac.", "I can't find Spotify or Apple Music on this Mac."))
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
                Text(L("La podrás cambiar cuando quieras en Ajustes › Notch", "You can change it any time in Settings › Notch"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Dónde va la canción entre una consulta a Spotify y la siguiente.
///
/// Spotify solo se consulta cada 2 s; entre medias se cuenta a partir de la última
/// posición que dio. Va aparte de la vista para poder probarlo.
struct TrackClock: Equatable {
    /// Segundos, con decimales.
    var base: Double
    var at: Date

    func exactPosition(now: Date, playing: Bool, duration: Int) -> Double {
        guard playing else { return base }
        let value = base + max(0, now.timeIntervalSince(at))
        return duration > 0 ? min(Double(duration), value) : value
    }

    /// Los segundos que se enseñan en texto.
    func position(now: Date, playing: Bool, duration: Int) -> Int {
        Int(exactPosition(now: now, playing: playing, duration: duration))
    }

    /// Lo que tarda Spotify en contestar o en aplicar una pausa: diferencias menores no se
    /// corrigen, porque corregirlas es justo el reajuste que se ve al pausar y seguir.
    static let tolerance: TimeInterval = 0.6

    /// Llega una posición nueva de Spotify. Si cuadra con lo que ya se enseña (menos de
    /// `tolerance`), se sigue igual; un salto de verdad (otro punto de la canción, otra
    /// canción, un parón de la red) sí se aplica.
    func rebased(reported: Double, now: Date, playing: Bool, duration: Int) -> TrackClock {
        let shown = exactPosition(now: now, playing: playing, duration: duration)
        if abs(reported - shown) < Self.tolerance { return self }
        return TrackClock(base: reported, at: now)
    }
}

/// Barra de progreso de la canción con tiempos. Arrastra para saltar a cualquier
/// punto, como en el reproductor real; un clic suelto no salta (distancia mínima).
struct TrackProgress: View {
    let position: Double
    let duration: Int
    var isPlaying = false
    let onSeek: (Int) -> Void

    @State private var dragFraction: Double?
    @State private var clock: TrackClock

    init(position: Double, duration: Int, isPlaying: Bool = false, onSeek: @escaping (Int) -> Void) {
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.onSeek = onSeek
        _clock = State(initialValue: TrackClock(base: position, at: Date()))
    }

    private var isDragging: Bool { dragFraction != nil }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let barHeight: CGFloat = isDragging ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: barHeight)
                    if let dragFraction {
                        Capsule()
                            .fill(.white)
                            .frame(width: max(3, geo.size.width * dragFraction), height: barHeight)
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .offset(x: geo.size.width * dragFraction - 5.5)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    } else {
                        // Desliza sola hasta el final de la canción (ver `SmoothProgressFill`).
                        SmoothProgressFill(clock: clock, duration: duration, playing: isPlaying)
                            .frame(height: barHeight)
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

            // El tiempo en texto, cada segundo mientras suena; en pausa, quieto.
            Group {
                if isPlaying && !isDragging {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        times(clock.position(now: context.date, playing: true, duration: duration))
                    }
                } else {
                    times(dragFraction.map { Int($0 * Double(duration)) }
                          ?? clock.position(now: .now, playing: isPlaying, duration: duration))
                }
            }
        }
        .onChange(of: position) { _, reported in
            clock = clock.rebased(reported: reported, now: .now, playing: isPlaying, duration: duration)
        }
        .onChange(of: duration) { _, _ in
            clock = TrackClock(base: position, at: .now)
        }
        .onChange(of: isPlaying) { wasPlaying, _ in
            // Al pausar se queda justo donde iba (con decimales; redondear a segundos la
            // hacía retroceder) y al seguir cuenta desde ahí.
            clock = TrackClock(base: clock.exactPosition(now: .now, playing: wasPlaying, duration: duration), at: .now)
        }
    }

    private func times(_ shown: Int) -> some View {
        HStack {
            Text(Self.time(shown))
            Spacer()
            Text(Self.time(duration))
        }
        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(isDragging ? 0.85 : 0.5))
    }

    private static func time(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

/// El relleno de la barra de la canción, deslizándose de forma continua.
///
/// Con SwiftUI, una animación así se calcula fotograma a fotograma en el propio
/// OmniMac (era lo que se comía el 9 % de CPU del principio). Aquí se le encarga a Core
/// Animation una sola vez, «de aquí al final de la canción, a velocidad constante», y
/// los fotogramas los pinta el servidor de ventanas. La app solo vuelve a intervenir
/// cuando hay algo nuevo: Spotify corrige la posición, pausas, saltas o cambia la canción.
struct SmoothProgressFill: NSViewRepresentable {
    let clock: TrackClock
    let duration: Int
    let playing: Bool

    func makeNSView(context: Context) -> FillView { FillView() }

    func updateNSView(_ view: FillView, context: Context) {
        view.configure(.init(clock: clock, duration: duration, playing: playing))
    }

    final class FillView: NSView {
        struct Configuration: Equatable {
            let clock: TrackClock
            let duration: Int
            let playing: Bool
        }

        private let fill = CALayer()
        private var configuration: Configuration?
        private var appliedSize: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            fill.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer?.addSublayer(fill)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

        func configure(_ new: Configuration) {
            // SwiftUI vuelve a llamar con lo mismo a menudo: rehacer la animación en cada
            // llamada la haría dar tirones.
            guard new != configuration else { return }
            configuration = new
            apply()
        }

        override func layout() {
            super.layout()
            if bounds.size != appliedSize { apply() }
        }

        private func apply() {
            guard let configuration, let layer, bounds.width > 0 else { return }
            appliedSize = bounds.size
            let width = bounds.width
            // El relleno mide lo que la pista y se desplaza a la izquierda lo que falta: así
            // su punta queda redondeada y la máscara de la pista recorta el resto.
            func offset(_ seconds: Double) -> CGFloat {
                guard configuration.duration > 0 else { return -width }
                let fraction = min(1, max(0, seconds / Double(configuration.duration)))
                return -width * CGFloat(1 - fraction)
            }
            let now = Date()
            let current = configuration.clock.exactPosition(now: now, playing: configuration.playing,
                                                             duration: configuration.duration)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.cornerRadius = bounds.height / 2
            fill.removeAllAnimations()
            // Tamaño y posición, no `frame`: con el desplazamiento anterior aún puesto,
            // asignar el marco hace que Core Animation compense moviendo la posición, y al
            // volver a configurarla (cada corrección de Spotify) la barra salía casi llena.
            fill.bounds = CGRect(origin: .zero, size: bounds.size)
            fill.position = CGPoint(x: bounds.midX, y: bounds.midY)
            fill.cornerRadius = bounds.height / 2
            fill.transform = CATransform3DMakeTranslation(offset(current), 0, 0)
            CATransaction.commit()

            let remaining = Double(configuration.duration) - current
            guard configuration.playing, remaining > 0 else { return }
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = offset(current)
            slide.toValue = 0
            slide.duration = remaining
            slide.timingFunction = CAMediaTimingFunction(name: .linear)
            slide.fillMode = .forwards
            slide.isRemovedOnCompletion = false
            fill.add(slide, forKey: "progress")
        }
    }
}
