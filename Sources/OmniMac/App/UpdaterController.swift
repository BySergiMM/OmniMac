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
        guard let lastCheck else { return L("Aún no se ha comprobado", "Not checked yet") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        return L("Última comprobación: \(formatter.localizedString(for: lastCheck, relativeTo: Date()))", "Last check: \(formatter.localizedString(for: lastCheck, relativeTo: Date()))")
    }
}
