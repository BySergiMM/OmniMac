import Foundation

/// Por qué se acabó una sesión de «mantener despierto».
///
/// Existe porque la sesión se puede parar sola y, hasta ahora, cuando eso pasaba con
/// la tapa cerrada el Mac se dormía en el acto y no quedaba ni rastro: se abría el
/// portátil, salía la pantalla de bloqueo y no había forma de saber qué había pasado.
/// La notificación no basta — se manda justo cuando el Mac se está durmiendo, así que
/// puede no llegar a entregarse nunca.
enum KeepAwakeEndReason: String, Codable {
    case manual
    case timer
    case lowBattery
    /// La app se cerró (al salir, o al reiniciarse para actualizarse).
    case appQuit
    /// Se apagó el módulo entero en Ajustes.
    case moduleOff
    /// Un disparador automático (cargador, pantalla externa) dejó de cumplirse.
    case trigger
}

/// El último final automático, para poder contarlo cuando el usuario vuelva.
struct KeepAwakeEnding: Codable, Equatable {
    let reason: KeepAwakeEndReason
    /// Nivel de batería en ese momento, si venía al caso.
    let batteryLevel: Int?
    let at: Date

    static let key = "keepawake.lastEnding"

    /// Los finales a mano no se guardan: el usuario ya sabe que lo apagó él.
    var worthTelling: Bool { reason != .manual }

    var explanation: String {
        switch reason {
        case .manual:
            return ""
        case .timer:
            return L("La sesión terminó porque se acabó el tiempo que le pusiste.",
                     "The session ended because the timer you set ran out.")
        case .lowBattery:
            let level = batteryLevel.map { "\($0) %" } ?? L("poca batería", "low battery")
            return L("La sesión se paró sola al bajar la batería a \(level). Si tenías la tapa cerrada, el Mac se durmió en ese momento.",
                     "The session stopped on its own when the battery dropped to \(level). If your lid was closed, your Mac went to sleep right then.")
        case .appQuit:
            return L("La sesión se paró porque OmniMac se cerró (al salir o al actualizarse).",
                     "The session stopped because OmniMac quit (either you closed it or it updated itself).")
        case .moduleOff:
            return L("La sesión se paró porque apagaste el módulo «Mantener despierto».",
                     "The session stopped because you turned the Keep awake module off.")
        case .trigger:
            return L("La sesión se paró porque dejó de cumplirse la condición que la había arrancado (cargador o pantalla externa).",
                     "The session stopped because the condition that started it — charger or external display — no longer holds.")
        }
    }
}

/// Qué hacer con la batería mientras hay una sesión activa.
///
/// Aparte para poder probarlo: la decisión importa mucho (con la tapa cerrada, parar
/// la sesión duerme el Mac en el acto) y no debe depender de abrir una ventana.
enum KeepAwakeBatteryRule {
    enum Decision: Equatable {
        case nothing
        /// Queda poco para el corte: avisar mientras la pantalla se pueda ver.
        case warn(level: Int)
        case stop(level: Int)
    }

    /// Cuánto antes del corte se avisa. Con la tapa abierta da tiempo a enchufar.
    static let warningMargin = 10

    static func decide(level: Int, hasBattery: Bool, isPluggedIn: Bool,
                       enabled: Bool, threshold: Int, alreadyWarned: Bool) -> Decision {
        // Con cargador no hay nada que proteger. `level > 0` descarta las lecturas
        // vacías de IOKit justo al arrancar, que si no cortarían la sesión al vuelo.
        guard enabled, hasBattery, !isPluggedIn, level > 0 else { return .nothing }
        if level <= threshold { return .stop(level: level) }
        if !alreadyWarned, level <= threshold + warningMargin { return .warn(level: level) }
        return .nothing
    }
}
