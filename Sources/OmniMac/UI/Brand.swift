import SwiftUI

/// Identidad de marca de OmniMac.
enum Brand {
    static let name = "OmniMac"
    static let tagline = L("Todo lo que le falta a tu Mac", "Everything your Mac is missing")

    /// Violeta OmniMac (#6C4DFF aprox.)
    static let accent = Color(red: 0.42, green: 0.30, blue: 1.0)
    static let accentLight = Color(red: 0.66, green: 0.45, blue: 1.0)
    static let ink = Color(red: 0.10, green: 0.06, blue: 0.28)

    static let gradient = LinearGradient(colors: [accent, accentLight],
                                         startPoint: .bottomLeading,
                                         endPoint: .topTrailing)

    /// Apoyar el proyecto. OmniMac es gratis y sin anuncios; si te ayuda, invita a un
    /// café. GitHub Sponsors (0 % de comisión, integrado con el repositorio) y Ko-fi
    /// (propinas puntuales sin que quien dona necesite cuenta). Cambia aquí los
    /// enlaces si mueves las páginas.
    static let sponsorsURL = URL(string: "https://github.com/sponsors/BySergiMM")!
    static let coffeeURL = URL(string: "https://ko-fi.com/seergiii")!
    static let repoURL = URL(string: "https://github.com/seergiii/OmniMac")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2"
    }
}
