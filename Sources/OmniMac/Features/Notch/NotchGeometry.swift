import AppKit

/// Toda la geometría del notch para una pantalla concreta.
///
/// Se calcula a partir de lo que dice la pantalla, **no** del modelo de Mac. Un
/// MacBook Pro de 14" y uno de 16" tienen notches de anchos distintos, la resolución
/// «Más espacio» cambia todos los puntos de golpe, y en un iMac, un Mac mini o un
/// monitor externo no hay notch en absoluto. Preguntar por `hw.model` obligaría a
/// mantener a mano una lista de modelos que se queda vieja cada septiembre; la
/// pantalla ya sabe todo lo que necesitamos.
///
/// Se recalcula entera cada vez que cambia la configuración de pantallas (ver
/// `NotchFeature.rebuild`).
struct NotchGeometry: Equatable {
    /// Notch físico (MacBook de 2021 en adelante). Si es `false` dibujamos una isla
    /// del mismo estilo colgando de la barra de menús.
    let hasNotch: Bool
    /// Tamaño del notch (o de la isla) en reposo.
    let notchSize: CGSize
    /// Tamaño del panel negro ya desplegado, sin el margen de la sombra.
    let expandedSize: CGSize
    /// Marco de la pantalla, para situarlo todo.
    let screenFrame: CGRect
    /// Ventana en reposo: el notch exacto, pegado al techo.
    let collapsedFrame: CGRect
    /// Zona que abre el notch al pasar el ratón (un poco más ancha que el notch).
    let hoverZone: CGRect
    /// Ventana desplegada, con margen extra para que la sombra no se recorte.
    let expandedFrame: CGRect
    /// El negro visible dentro de la ventana desplegada: es lo que cuenta para
    /// decidir si el ratón «ha salido».
    let bodyFrame: CGRect
    /// Margen que se añade a los lados y abajo para la sombra.
    let shadowMargin: CGFloat

    /// Ancho del notch cuando la pantalla dice que lo tiene pero no publica las dos
    /// zonas de la barra de menús. Todos los MacBook con notch rondan este ancho.
    static let fallbackNotchWidth: CGFloat = 196
    /// La isla de las pantallas sin notch se dimensiona con el ancho de la pantalla,
    /// entre estos dos límites, para que no quede ridícula en un ultrapanorámico ni
    /// enorme en un monitor pequeño.
    static let islandWidthRange: ClosedRange<CGFloat> = 180...260
    /// Proporción del ancho de pantalla que ocupa la isla (en un MacBook de 14" da
    /// justo el ancho del notch real, así que se ve igual en todas partes).
    static let islandWidthRatio: CGFloat = 0.13
    /// Alto del panel desplegado. Fijo: es un diseño, no una proporción.
    static let expandedHeight: CGFloat = 196
    /// Margen libre a cada lado del panel desplegado respecto al borde de la pantalla.
    static let screenMargin: CGFloat = 40

    /// - Parameters:
    ///   - frame: marco de la pantalla, en puntos.
    ///   - safeAreaTop: alto del área segura superior. Solo es mayor que cero si la
    ///     pantalla tiene notch físico.
    ///   - auxiliaryWidths: ancho de las dos zonas de barra de menús que quedan a los
    ///     lados del notch. `nil` en pantallas sin notch (o si macOS no las publica).
    ///   - menuBarHeight: alto de la barra de menús de esa pantalla.
    init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryWidths: (left: CGFloat, right: CGFloat)?, menuBarHeight: CGFloat) {
        let hasNotch = safeAreaTop > 0
        self.hasNotch = hasNotch
        self.screenFrame = frame

        // Alto: con notch, el que diga el área segura. Sin notch, la isla cuelga un
        // poco por debajo de la barra de menús para que se vea que está ahí.
        let height = hasNotch ? safeAreaTop : max(30, menuBarHeight - 1)

        // Ancho: con notch real es lo que queda entre las dos mitades de la barra de
        // menús. Sin notch, proporcional a la pantalla y acotado.
        let width: CGFloat
        if hasNotch, let aux = auxiliaryWidths, aux.left > 0, aux.right > 0 {
            width = frame.width - aux.left - aux.right
        } else if hasNotch {
            width = Self.fallbackNotchWidth
        } else {
            width = min(max(frame.width * Self.islandWidthRatio, Self.islandWidthRange.lowerBound),
                        Self.islandWidthRange.upperBound)
        }
        notchSize = CGSize(width: width, height: height)

        // A cada lado del notch deben caber las cinco pestañas de la izquierda
        // (16 + 5×32 + 4×6 + 8 = 208 pt) y el grupo de la derecha; de ahí el mínimo.
        // Y nunca más ancho que la pantalla, que en un monitor pequeño se saldría.
        let wanted = max(580, width + NotchModel.sideClearance * 2)
        let expandedWidth = min(wanted, max(width, frame.width - Self.screenMargin))
        expandedSize = CGSize(width: expandedWidth, height: Self.expandedHeight)

        collapsedFrame = CGRect(x: frame.midX - width / 2,
                                y: frame.maxY - height,
                                width: width,
                                height: height)
        hoverZone = CGRect(x: collapsedFrame.minX - 20,
                           y: collapsedFrame.minY - 4,
                           width: width + 40,
                           height: height + 4)

        // La ventana es más grande que el panel negro: el margen extra (lados y abajo)
        // deja sitio para que la sombra no se recorte. El borde superior sigue pegado
        // al techo de la pantalla para fundirse con el notch físico.
        let margin: CGFloat = 36
        shadowMargin = margin
        expandedFrame = CGRect(x: frame.midX - (expandedWidth + margin * 2) / 2,
                               y: frame.maxY - Self.expandedHeight - margin,
                               width: expandedWidth + margin * 2,
                               height: Self.expandedHeight + margin)
        bodyFrame = CGRect(x: expandedFrame.minX + margin - NotchExpandedShape.flare,
                           y: expandedFrame.maxY - Self.expandedHeight,
                           width: expandedWidth + NotchExpandedShape.flare * 2,
                           height: Self.expandedHeight)
    }

    /// La misma geometría, leída de una pantalla de verdad.
    init(screen: NSScreen) {
        let aux: (left: CGFloat, right: CGFloat)?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            aux = (left.width, right.width)
        } else {
            aux = nil
        }
        self.init(frame: screen.frame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryWidths: aux,
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
