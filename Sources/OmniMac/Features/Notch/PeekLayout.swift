import CoreGraphics

/// Dónde sale el vistazo rápido (canción nueva, cargador, avisos, volumen y brillo).
///
/// «Debajo» es lo de siempre: el negro baja un poco y el texto va bajo el notch.
/// «A los lados» no baja nada: el negro se ensancha a la altura de la barra de menús,
/// con el icono a la izquierda del notch y el texto a la derecha, para no tapar la
/// parte de la pantalla en la que se trabaja (lo pidieron en el issue #4).
enum PeekPlacement: String, CaseIterable {
    case below
    case sides

    static let defaultsKey = "notch.peekPlacement"

    var title: String {
        switch self {
        case .below: L("Debajo del notch", "Below the notch")
        case .sides: L("A los lados del notch", "Beside the notch")
        }
    }
}

/// Tamaño del vistazo según dónde va y lo que tiene que caber.
///
/// Va aparte de la vista para poder probarlo: si las alas no son simétricas, el
/// negro deja de estar centrado sobre el notch físico y se ve un trozo descolgado.
struct PeekLayout: Equatable {
    /// Tamaño del negro (y del panel) entero.
    let size: CGSize
    /// Ancho de cada ala a los lados del notch; 0 si va debajo.
    let wing: CGFloat

    /// Ala de la actividad «música sonando». Con 50 se veía apretada contra la
    /// carátula; una quinta parte más le da aire sin tapar la barra de menús.
    static let activityWing: CGFloat = 60
    /// Lo que ocupa la barra del HUD de volumen y brillo.
    static let levelBarWidth: CGFloat = 96
    /// Lo que crece el negro hacia abajo cuando el vistazo va debajo.
    static let belowExtraHeight: CGFloat = 30
    /// Margen libre a cada lado de la pantalla.
    static let screenMargin: CGFloat = 40
    static let minWing: CGFloat = 60
    /// Más allá de esto el texto se corta con «…»: unas alas muy largas a la altura
    /// de la barra de menús taparían sus menús y sus iconos.
    static let maxWing: CGFloat = 220

    /// - Parameters:
    ///   - leadingWidth: lo que va a la izquierda (icono y, si lo hay, el color).
    ///   - contentWidth: el texto o la barra.
    static func make(placement: PeekPlacement,
                     notchSize: CGSize,
                     leadingWidth: CGFloat,
                     contentWidth: CGFloat,
                     screenWidth: CGFloat,
                     flare: CGFloat) -> PeekLayout {
        switch placement {
        case .below:
            // Icono, separaciones y los rebordes curvos de arriba.
            let extras = leadingWidth + 12 + (flare + 12) * 2 + 16
            let width = min(max(notchSize.width + 110, contentWidth + extras),
                            screenWidth - screenMargin * 2)
            return PeekLayout(size: CGSize(width: width, height: notchSize.height + belowExtraHeight), wing: 0)
        case .sides:
            // Las dos alas iguales, para que el conjunto siga centrado en el notch:
            // la más ancha manda.
            let padding = flare + 10 + 8
            var wing = min(max(max(leadingWidth, contentWidth) + padding, minWing), maxWing)
            wing = min(wing, max(0, (screenWidth - screenMargin * 2 - notchSize.width) / 2))
            return PeekLayout(size: CGSize(width: notchSize.width + wing * 2, height: notchSize.height), wing: wing)
        }
    }
}
