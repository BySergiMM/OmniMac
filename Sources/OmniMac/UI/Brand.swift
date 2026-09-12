import SwiftUI

/// Identidad de marca de OmniMac.
enum Brand {
    static let name = "OmniMac"
    static let tagline = L("La Dynamic Island que tu Mac nunca tuvo", "The Dynamic Island your Mac never had")

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
    static let repoURL = URL(string: "https://github.com/BySergiMM/OmniMac")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2"
    }
}

// MARK: - El destello de la marca

extension Brand {
    /// El icono de la barra de menús, dibujado igual que el de la app.
    ///
    /// Antes se usaba el símbolo `sparkles` del sistema, que tiene **tres** estrellas
    /// y una disposición distinta: en la barra se veía un dibujo y en la web otro.
    /// Esto reproduce la composición del icono de la app —una estrella grande y otra
    /// pequeña arriba a la derecha— con las proporciones medidas sobre el propio PNG:
    /// la grande ocupa 0,371 del icono y la pequeña 0,105, con los centros en
    /// (0,498 · 0,537) y (0,662 · 0,365).
    ///
    /// Va como *template*: macOS lo pinta blanco o negro según la barra, y así se ve
    /// bien en claro, en oscuro y sobre un fondo de pantalla cualquiera.
    static func menuBarIcon(size: CGFloat = 18) -> NSImage {
        // Proporciones medidas sobre docs/site/img/icon.png, en fracción del icono.
        let bigCenter = CGPoint(x: 0.498, y: 0.537)
        let bigRadius: CGFloat = 0.1855
        let smallCenter = CGPoint(x: 0.662, y: 0.365)
        let smallRadius: CGFloat = 0.0525

        // Se encuadra la composición (las dos estrellas) dentro del lienzo, con un
        // margen para que no toque los bordes de la barra.
        let minX = min(bigCenter.x - bigRadius, smallCenter.x - smallRadius)
        let maxX = max(bigCenter.x + bigRadius, smallCenter.x + smallRadius)
        let minY = min(bigCenter.y - bigRadius, smallCenter.y - smallRadius)
        let maxY = max(bigCenter.y + bigRadius, smallCenter.y + smallRadius)
        let span = max(maxX - minX, maxY - minY)
        let inset: CGFloat = size * 0.06
        let scale = (size - inset * 2) / span

        func place(_ point: CGPoint) -> CGPoint {
            // El eje Y del icono va hacia abajo y el de dibujo hacia arriba.
            CGPoint(x: inset + (point.x - minX) * scale,
                    y: size - (inset + (point.y - minY) * scale))
        }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let path = NSBezierPath()
            path.append(Self.sparkle(center: place(bigCenter), radius: bigRadius * scale))
            path.append(Self.sparkle(center: place(smallCenter), radius: smallRadius * scale))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Una estrella de cuatro puntas con los lados cóncavos.
    ///
    /// Cada lado es una curva cúbica entre dos puntas, con los puntos de control
    /// sobre los ejes a `waist · radio` del centro. Ese número es lo único que decide
    /// si el destello sale afilado o gordo: con 0 se pega al centro y queda como una
    /// aguja; con 1 sería un rombo.
    ///
    /// **0,4 está medido, no elegido a ojo.** Se sacó el perfil de la estrella del
    /// icono de la app píxel a píxel —a 0,45 del radio mide 0,138 de semianchura— y
    /// se buscó la curva que lo reproduce.
    private static let waist: CGFloat = 0.4

    private static func sparkle(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        let r = radius, k = radius * waist
        let tips = [CGPoint(x: center.x, y: center.y + r),   // arriba
                    CGPoint(x: center.x + r, y: center.y),   // derecha
                    CGPoint(x: center.x, y: center.y - r),   // abajo
                    CGPoint(x: center.x - r, y: center.y)]   // izquierda
        // Los controles de cada tramo, sobre los ejes y a `k` del centro.
        let controls = [(CGPoint(x: center.x, y: center.y + k), CGPoint(x: center.x + k, y: center.y)),
                        (CGPoint(x: center.x + k, y: center.y), CGPoint(x: center.x, y: center.y - k)),
                        (CGPoint(x: center.x, y: center.y - k), CGPoint(x: center.x - k, y: center.y)),
                        (CGPoint(x: center.x - k, y: center.y), CGPoint(x: center.x, y: center.y + k))]
        let path = NSBezierPath()
        path.move(to: tips[0])
        for index in 0..<4 {
            path.curve(to: tips[(index + 1) % 4],
                       controlPoint1: controls[index].0,
                       controlPoint2: controls[index].1)
        }
        path.close()
        return path
    }
}
