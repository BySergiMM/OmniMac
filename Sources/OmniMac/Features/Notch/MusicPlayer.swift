import AppKit

/// Reproductores de música que OmniMac sabe controlar por AppleScript.
enum MusicPlayer: String, CaseIterable, Identifiable {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var id: String { rawValue }
    var bundleID: String { rawValue }

    /// Nombre para AppleScript (no cambia con el idioma del sistema).
    var scriptName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Preferencia del usuario

    private static let defaultsKey = "media.preferredPlayer"

    /// Reproductor elegido por el usuario (nil = aún no ha elegido).
    static var preferred: MusicPlayer? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
            return MusicPlayer(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    static var installed: [MusicPlayer] { allCases.filter(\.isInstalled) }
}
