import Foundation

/// Mover un icono del notch de sitio arrastrándolo.
///
/// Está aparte de la vista porque tiene una sutileza que conviene tener probada: en
/// el notch solo se ven las pestañas encendidas, pero el orden que se guarda las
/// incluye todas. Al mover un icono dos sitios a la derecha hay que contar dos
/// **visibles**, y dejar las apagadas donde estaban.
enum TabReorder {
    /// - Parameters:
    ///   - tab: la pestaña que se arrastra.
    ///   - shift: cuántos sitios se mueve, contando solo las visibles (negativo, a la izquierda).
    ///   - order: el orden completo, guardado.
    ///   - visible: las pestañas que se ven ahora mismo.
    /// - Returns: el orden completo ya cambiado.
    static func move(_ tab: NotchTab, by shift: Int, in order: [NotchTab], visible: Set<NotchTab>) -> [NotchTab] {
        guard shift != 0, visible.contains(tab) else { return order }
        var shown = order.filter { visible.contains($0) }
        guard let from = shown.firstIndex(of: tab) else { return order }
        let to = min(max(from + shift, 0), shown.count - 1)
        guard to != from else { return order }
        shown.remove(at: from)
        shown.insert(tab, at: to)

        // Las apagadas se quedan en su hueco; los huecos de las visibles se rellenan
        // con el orden nuevo.
        var result: [NotchTab] = []
        var next = shown.makeIterator()
        for item in order {
            if visible.contains(item) {
                if let replacement = next.next() { result.append(replacement) }
            } else {
                result.append(item)
            }
        }
        return result
    }
}
