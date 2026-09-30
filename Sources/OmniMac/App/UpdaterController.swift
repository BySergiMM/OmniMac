import AppKit
import Combine
import Sparkle

/// Actualizaciones automáticas con Sparkle. El appcast vive en GitHub Releases
/// (`SUFeedURL` en Info.plist) y cada versión va firmada con la clave EdDSA
/// (`SUPublicEDKey`). Comprueba una vez al día y avisa cuando hay algo nuevo.
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    @Published var automaticChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }
    var canCheck: Bool { controller.updater.canCheckForUpdates }
    /// true mientras Sparkle descarga o instala algo (la limpieza de caché no toca su carpeta entonces).
    var sessionInProgress: Bool { controller.updater.sessionInProgress }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
    }

    /// Comprobación manual: enseña la ventana de Sparkle con el resultado.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var lastCheckText: String {
        UpdateCheckText.lastCheck(lastCheck, spanish: Localization.isSpanish)
    }
}

/// El texto de «última comprobación» que enseña Ajustes. Vive fuera de
/// `UpdaterController` porque ese arranca Sparkle al crearse y no se puede
/// instanciar en una prueba.
enum UpdateCheckText {
    /// La fecha relativa ha de salir en el idioma de la frase que la rodea. Antes el
    /// formateador llevaba siempre `es_ES` y en inglés se leía «Last check: hace 2
    /// horas». El idioma se recibe por parámetro (en la app, el efectivo de la
    /// interfaz) para poder probar los dos sin depender del Mac donde corra la prueba.
    static func lastCheck(_ date: Date?, now: Date = Date(), spanish: Bool) -> String {
        guard let date else { return spanish ? "Aún no se ha comprobado" : "Not checked yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: spanish ? "es_ES" : "en_US")
        let when = formatter.localizedString(for: date, relativeTo: now)
        return spanish ? "Última comprobación: \(when)" : "Last check: \(when)"
    }
}
