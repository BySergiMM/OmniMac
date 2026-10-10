import CoreGraphics

/// Decide cuándo el ratón puede cambiar la selección del selector ⌘Tab.
///
/// El panel aparece en el centro de la pantalla: si el ratón ya estaba ahí quieto,
/// SwiftUI avisaba de que estaba «encima» de una celda y la elegía, de modo que ⌘Tab
/// llevaba a la ventana que había bajo el cursor en vez de a la anterior. Solo
/// cuenta lo que el usuario mueve: si la posición no ha cambiado desde la última
/// vez, no es el usuario apuntando (es el panel apareciendo o la cuadrícula
/// desplazándose bajo un ratón quieto al moverse con el teclado).
struct SwitcherHoverGate {
    private var lastLocation: CGPoint?

    /// Al abrir el selector: la posición actual del ratón todavía no es un gesto.
    mutating func reset(at location: CGPoint) {
        lastLocation = location
    }

    /// `true` si el ratón se ha movido desde la última vez, por poco que sea.
    mutating func shouldFollow(mouseAt location: CGPoint) -> Bool {
        defer { lastLocation = location }
        return location != lastLocation
    }

    /// Celda bajo el ratón. El hover de SwiftUI se salta movimientos en un panel que no
    /// tiene el foco (con el ratón rápido la celda no se enteraba), así que se calcula a
    /// mano: `mouse` en coordenadas de pantalla (origen abajo), `panelFrame` también, y
    /// `cellFrames` en las del contenido del panel (origen arriba, como SwiftUI).
    /// Por encima de `gridTop` está la cabecera: una celda desplazada hacia arriba, o
    /// una que asoma por abajo, tiene marco fuera de lo que se ve y no cuenta ahí.
    static func cell(at mouse: CGPoint, panelFrame: CGRect, gridTop: CGFloat = 0, cellFrames: [Int: CGRect]) -> Int? {
        let local = CGPoint(x: mouse.x - panelFrame.minX, y: panelFrame.maxY - mouse.y)
        let grid = CGRect(x: 0, y: gridTop, width: panelFrame.width, height: panelFrame.height - gridTop)
        guard grid.contains(local) else { return nil }
        return cellFrames.first { $0.value.contains(local) }?.key
    }
}
