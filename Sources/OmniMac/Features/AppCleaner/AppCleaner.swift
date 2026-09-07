import AppKit
import Combine

/// Desinstalador de apps: encuentra la app, busca lo que deja por el sistema y lo
/// manda **a la papelera**, nunca lo borra del todo. Si algo se lleva por delante
/// que no debía, se recupera desde la papelera como cualquier otro archivo.
@MainActor
final class AppCleaner: ObservableObject {
    static let shared = AppCleaner()

    /// Apps instaladas, ordenadas por nombre.
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    /// App elegida y sus restos.
    @Published private(set) var selected: InstalledApp?
    @Published private(set) var leftovers: [Leftover] = []
    @Published private(set) var scanning = false
    /// Qué se va a mandar a la papelera (la app siempre; los restos, los marcados).
    @Published var checked: Set<URL> = []
    /// Resultado de la última limpieza, para enseñarlo en Ajustes.
    @Published private(set) var lastResult: String?

    /// Carpetas donde se buscan apps.
    nonisolated private static let appFolders = ["/Applications", "/Applications/Utilities",
                                     NSHomeDirectory() + "/Applications"]

    private init() {}

    /// Total de lo que está marcado (la app más los restos marcados).
    var checkedSize: Int64 {
        var total: Int64 = 0
        if let selected, checked.contains(selected.url) { total += selected.size }
        for leftover in leftovers where checked.contains(leftover.url) { total += leftover.size }
        return total
    }

    var checkedSizeText: String { CacheCleaner.format(checkedSize) }

    // MARK: - Listar apps

    func loadApps() {
        guard !loading else { return }
        loading = true
        let ownBundle = Bundle.main.bundleURL.standardizedFileURL
        Task.detached(priority: .userInitiated) {
            let found = Self.scanApps(excluding: ownBundle)
            await MainActor.run {
                self.apps = found
                self.loading = false
            }
        }
    }

    nonisolated private static func scanApps(excluding ownBundle: URL) -> [InstalledApp] {
        let fm = FileManager.default
        var result: [InstalledApp] = []
        var seen: Set<URL> = []
        for folder in appFolders {
            let url = URL(fileURLWithPath: folder)
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let appURL = url.appending(path: name).standardizedFileURL
                // La propia OmniMac no se ofrece: no va a desinstalarse a sí misma
                // mientras está corriendo.
                guard appURL != ownBundle, !seen.contains(appURL) else { continue }
                seen.insert(appURL)
                guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier,
                      !LeftoverMatcher.isProtected(bundleID: id) else { continue }
                let display = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? String(name.dropLast(4))
                result.append(InstalledApp(url: appURL,
                                           name: display,
                                           bundleID: id,
                                           version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                           size: CacheCleaner.directorySize(appURL)))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Buscar restos

    func select(_ app: InstalledApp) {
        selected = app
        leftovers = []
        checked = [app.url]      // la app, siempre marcada
        scanning = true
        Task.detached(priority: .userInitiated) {
            let found = Self.scanLeftovers(for: app)
            await MainActor.run {
                guard self.selected == app else { return }   // se cambió de app mientras tanto
                self.leftovers = found
                // Los de dentro de la carpeta del usuario van marcados; los del
                // sistema no, porque piden contraseña de administrador.
                self.checked.formUnion(found.filter { !$0.needsAdmin }.map(\.url))
                self.scanning = false
            }
        }
    }

    func clearSelection() {
        selected = nil
        leftovers = []
        checked = []
    }

    nonisolated private static func scanLeftovers(for app: InstalledApp) -> [Leftover] {
        let fm = FileManager.default
        var result: [Leftover] = []
        for place in LeftoverPlace.all {
            let folder = place.url
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where LeftoverMatcher.belongs(fileName: name,
                                                            bundleID: app.bundleID,
                                                            appName: app.name,
                                                            allowNameMatch: place.allowNameMatch) {
                let url = folder.appending(path: name)
                result.append(Leftover(place: place.title,
                                       url: url,
                                       size: CacheCleaner.directorySize(url),
                                       needsAdmin: !place.inHome))
            }

            // Segunda pasada: las apps que guardan sus cosas dentro de una carpeta
            // con el nombre del fabricante (Application Support/Google/Chrome). Solo
            // en las carpetas donde eso se estila, y sin tocar nunca la del fabricante.
            guard place.allowNameMatch, let vendor = LeftoverMatcher.vendor(bundleID: app.bundleID) else { continue }
            for name in names where name.compare(vendor, options: .caseInsensitive) == .orderedSame {
                let vendorFolder = folder.appending(path: name)
                guard let inside = try? fm.contentsOfDirectory(atPath: vendorFolder.path) else { continue }
                for child in inside where LeftoverMatcher.belongsInsideVendorFolder(fileName: child,
                                                                                   bundleID: app.bundleID,
                                                                                   appName: app.name) {
                    let url = vendorFolder.appending(path: child)
                    result.append(Leftover(place: place.title,
                                           url: url,
                                           size: CacheCleaner.directorySize(url),
                                           needsAdmin: !place.inHome))
                }
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    // MARK: - A la papelera

    /// Manda a la papelera lo marcado. Devuelve cuántos elementos no pudo mover.
    @discardableResult
    func trashChecked() -> Int {
        let fm = FileManager.default
        var freed: Int64 = 0
        var failed = 0
        var trashedApp = false

        // Los restos primero y la app al final: si algo falla, no dejamos una app a
        // medio desinstalar sin sus datos.
        var targets: [(URL, Int64)] = leftovers.filter { checked.contains($0.url) }.map { ($0.url, $0.size) }
        if let selected, checked.contains(selected.url) {
            targets.append((selected.url, selected.size))
            trashedApp = true
        }

        for (url, size) in targets {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                freed += size
            } catch {
                failed += 1
            }
        }

        lastResult = failed == 0
            ? L("A la papelera: \(CacheCleaner.format(freed))", "Moved to Trash: \(CacheCleaner.format(freed))")
            : L("A la papelera: \(CacheCleaner.format(freed)). \(failed) sin permiso (pide contraseña de administrador).",
                "Moved to Trash: \(CacheCleaner.format(freed)). \(failed) needed an administrator password.")

        if trashedApp, failed == 0 {
            clearSelection()
            loadApps()
        } else if let selected {
            select(selected)   // volver a mirar qué queda
        }
        return failed
    }
}
