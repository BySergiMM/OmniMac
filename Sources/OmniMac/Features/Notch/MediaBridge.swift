import AppKit
import Combine

struct NowPlayingInfo: Equatable {
    let playerName: String
    let bundleID: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let artworkURL: String?
    let position: Int   // segundos
    let duration: Int   // segundos
}

/// Lee y controla la reproducción de Spotify y Apple Music mediante AppleScript
/// (sin APIs privadas). Usa el reproductor asignado por el usuario y puede
/// lanzarlo si no está abierto; si no hay asignado, usa el que esté corriendo.
final class MediaBridge: ObservableObject {
    @Published private(set) var nowPlaying: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    /// true mientras lanzamos el reproductor asignado (para enseñar un spinner).
    @Published private(set) var launching = false

    private var timer: Timer?
    private var watchObservers: [Any] = []
    private var polling = false
    /// Se llama (en el hilo principal) cuando cambia la canción.
    var onTrackChange: ((NowPlayingInfo) -> Void)?
    private var lastTrackKey: String?
    private var lastArtworkURL: String?
    /// Última pulsación de play/pausa: mientras sea reciente, la UI se fía del
    /// estado optimista y no de sondeos que aún traen el estado anterior.
    private var lastPlayPauseAt: Date = .distantPast
    private let queue = DispatchQueue(label: "com.seergiii.omnimac.media")
    /// Solo para las capturas de la web (`--snapshots`): datos fijos, sin sondear.
    private var sampleMode = false

    func useSample(_ info: NowPlayingInfo, artwork: NSImage?) {
        sampleMode = true
        nowPlaying = info
        self.artwork = artwork
    }

    func startPolling() {
        guard timer == nil, !sampleMode else { return }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.4
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Vigilancia con el notch plegado (para el vistazo rápido) SIN sondear: Spotify
    /// y Música anuncian cada cambio de canción o de estado con una notificación
    /// distribuida. Solo entonces consultamos una vez por AppleScript. Con el ratón
    /// quieto y la misma canción, cero trabajo (sondear cada 3 s costaba 0,35 % de CPU).
    func startWatching() {
        guard watchObservers.isEmpty, !sampleMode else { return }
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            watchObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self, self.activePlayer != nil else { return }
                self.poll()
            })
        }
        // Estado actual al empezar (por si ya está sonando algo).
        if activePlayer != nil { poll() }
    }

    func stopWatching() {
        let center = DistributedNotificationCenter.default()
        watchObservers.forEach { center.removeObserver($0) }
        watchObservers = []
    }

    // MARK: - Controles

    func playPause() {
        if let player = activePlayer {
            // Respuesta inmediata en la UI (la carátula se "enciende" al instante);
            // el siguiente poll confirma el estado real.
            lastPlayPauseAt = Date()
            if let info = nowPlaying {
                nowPlaying = NowPlayingInfo(playerName: info.playerName, bundleID: info.bundleID,
                                            title: info.title, artist: info.artist,
                                            isPlaying: !info.isPlaying, artworkURL: info.artworkURL,
                                            position: info.position, duration: info.duration)
            }
            command("playpause", on: player)
        } else if let preferred = MusicPlayer.preferred {
            launchAndPlay(preferred)
        }
    }

    func nextTrack() {
        guard let player = activePlayer else { return }
        command("next track", on: player)
    }

    /// Salta a un punto de la canción (en segundos).
    func seek(to seconds: Int) {
        guard let player = activePlayer else { return }
        // Actualización optimista: la barra se queda donde la soltaste mientras
        // el reproductor obedece (el siguiente poll confirma la posición real).
        if let info = nowPlaying {
            nowPlaying = NowPlayingInfo(playerName: info.playerName,
                                        bundleID: info.bundleID,
                                        title: info.title,
                                        artist: info.artist,
                                        isPlaying: info.isPlaying,
                                        artworkURL: info.artworkURL,
                                        position: seconds,
                                        duration: info.duration)
        }
        command("set player position to \(seconds)", on: player)
    }

    func previousTrack() {
        guard let player = activePlayer else { return }
        command("previous track", on: player)
    }

    /// Lanza el reproductor (sin ventana en primer plano si se puede) y le da al play
    /// en cuanto responde al AppleScript.
    func launchAndPlay(_ player: MusicPlayer) {
        guard !launching else { return }
        launching = true

        queue.async { [weak self] in
            // `launch` de AppleScript abre la app; después reintentamos `play`
            // hasta que el proceso esté listo (Spotify tarda un par de segundos).
            _ = self?.runOnce("tell application \"\(player.scriptName)\" to launch")
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.7)
                if self?.runOnce("tell application \"\(player.scriptName)\" to play") != nil { break }
            }
            DispatchQueue.main.async {
                self?.launching = false
                self?.poll()
            }
        }
    }

    // MARK: - Interno

    /// El reproductor que toca controlar: el asignado si está abierto; si no,
    /// cualquiera que esté sonando ya (respetamos lo que el usuario tenga en uso).
    private var activePlayer: MusicPlayer? {
        if let preferred = MusicPlayer.preferred, preferred.isRunning {
            return preferred
        }
        return MusicPlayer.installed.first(where: \.isRunning)
    }

    private func command(_ command: String, on player: MusicPlayer) {
        let script = "tell application \"\(player.scriptName)\" to \(command)"
        queue.async { [weak self] in
            _ = self?.runOnce(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.poll()
            }
        }
    }

    private func poll() {
        guard !sampleMode else { return }
        guard !polling else { return }
        guard let player = activePlayer else {
            if nowPlaying != nil {
                nowPlaying = nil
                artwork = nil
                lastArtworkURL = nil
            }
            return
        }

        // Los números se devuelven como enteros (div) para evitar el separador
        // decimal localizado de AppleScript.
        let script: String
        if player == .spotify {
            script = """
            tell application "Spotify"
                if player state is stopped then return ""
                set trackName to name of current track
                set trackArtist to artist of current track
                set stateText to (player state as string)
                set artURL to artwork url of current track
                set posSec to (player position) div 1
                set durSec to (duration of current track) div 1000
                return trackName & "|~|" & trackArtist & "|~|" & stateText & "|~|" & artURL & "|~|" & posSec & "|~|" & durSec
            end tell
            """
        } else {
            script = """
            tell application "Music"
                if player state is stopped then return ""
                set trackName to name of current track
                set trackArtist to artist of current track
                set stateText to (player state as string)
                set posSec to (player position) div 1
                set durSec to (duration of current track) div 1
                return trackName & "|~|" & trackArtist & "|~|" & stateText & "|~||~|" & posSec & "|~|" & durSec
            end tell
            """
        }

        polling = true
        queue.async { [weak self] in
            let output = self?.runCached(script)
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                guard let output, !output.isEmpty else {
                    self.nowPlaying = nil
                    self.artwork = nil
                    self.lastArtworkURL = nil
                    self.lastTrackKey = nil
                    return
                }
                let parts = output.components(separatedBy: "|~|")
                guard parts.count >= 6 else { return }
                // Si acabas de pulsar play/pausa (varias veces incluso), el reproductor
                // puede no haber aplicado aún el último toque: mantenemos el estado
                // optimista para que la carátula no parpadee entre ambos.
                var isPlaying = parts[2] == "playing"
                if let current = self.nowPlaying, Date().timeIntervalSince(self.lastPlayPauseAt) < 1.2 {
                    isPlaying = current.isPlaying
                }
                let info = NowPlayingInfo(playerName: player.displayName,
                                          bundleID: player.bundleID,
                                          title: parts[0],
                                          artist: parts[1],
                                          isPlaying: isPlaying,
                                          artworkURL: parts[3].isEmpty ? nil : parts[3],
                                          position: Int(parts[4]) ?? 0,
                                          duration: Int(parts[5]) ?? 0)
                self.nowPlaying = info
                self.updateArtwork(info)
                let key = info.title + "\u{1}" + info.artist
                if key != self.lastTrackKey, info.isPlaying || self.lastTrackKey != nil {
                    self.onTrackChange?(info)
                }
                self.lastTrackKey = key
            }
        }
    }

    private func updateArtwork(_ info: NowPlayingInfo) {
        guard info.artworkURL != lastArtworkURL else { return }
        lastArtworkURL = info.artworkURL
        guard let urlString = info.artworkURL, let url = URL(string: urlString) else {
            artwork = nil
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = image }
        }.resume()
    }

    // MARK: - AppleScript en proceso
    // Antes cada consulta lanzaba un proceso `osascript` (fork+exec, ~50 ms de CPU).
    // NSAppleScript en una cola en serie cuesta ~1 ms, y los scripts calientes del
    // poll se compilan una sola vez.

    private var cachedScripts: [String: NSAppleScript] = [:]

    /// Para los scripts del poll: compilados una vez y reutilizados.
    private func runCached(_ source: String) -> String? {
        dispatchPrecondition(condition: .onQueue(queue))
        let script: NSAppleScript
        if let cached = cachedScripts[source] {
            script = cached
        } else if let fresh = NSAppleScript(source: source) {
            cachedScripts[source] = fresh
            script = fresh
        } else {
            return nil
        }
        return Self.execute(script)
    }

    /// Para órdenes puntuales (play, seek…): compilar y tirar — no se cachean
    /// porque el seek genera un script distinto por posición.
    private func runOnce(_ source: String) -> String? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let script = NSAppleScript(source: source) else { return nil }
        return Self.execute(script)
    }

    private static func execute(_ script: NSAppleScript) -> String? {
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue ?? ""
    }
}
