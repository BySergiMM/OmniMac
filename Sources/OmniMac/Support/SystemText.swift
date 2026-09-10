import Foundation

/// Nombres que nos da el sistema —de apps y de procesos— y que a veces llegan con la
/// codificación rota.
///
/// El caso real: el servicio de máquina virtual de Claude sale en macOS como
/// «Servicio de la m√°quina virtual para Claude». El nombre se guardó en UTF-8 y
/// alguien lo leyó como MacRoman antes de llegar aquí: la «á» es C3 A1 en UTF-8, y en
/// MacRoman C3 es «√» y A1 es «°». No lo rompemos nosotros —`localizedName` ya lo
/// devuelve así—, pero quien lo ve en OmniMac no tiene por qué saberlo.
enum SystemText {

    /// Deshace ese error si es exactamente ese error. Si no, devuelve el texto tal cual.
    ///
    /// Tiene que cuadrar por los dos lados para tocar nada:
    ///
    /// - El texto lleva alguna marca de este error: `√` o `¬`, que abren todas las
    ///   letras con tilde, la eñe y el punto medio, o `‚Ä`, que abre las comillas
    ///   tipográficas, las rayas y el euro. Sin marca ni se intenta: un «Café» bien
    ///   escrito se queda como está.
    /// - El texto entero se puede escribir en MacRoman, y los bytes que salen son
    ///   UTF-8 válido. Si falla cualquiera de las dos cosas, no era este error: un
    ///   «√2» de verdad da bytes que no son UTF-8, y tampoco se toca.
    static func repaired(_ text: String) -> String {
        guard markers.contains(where: { text.contains($0) }),
              let bytes = text.data(using: .macOSRoman),
              let fixed = String(data: bytes, encoding: .utf8),
              fixed != text
        else { return text }
        return fixed
    }

    private static let markers = ["√", "¬", "‚Ä"]
}
