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

    /// Restos de apps que ya no están instaladas.
    @Published private(set) var orphans: [OrphanLeftover] = []
    @Published private(set) var scanningOrphans = false
    /// La lista ya está, pero los tamaños siguen llegando.
    @Published private(set) var measuringOrphans = false
    /// Nunca se marcan solos: aquí el usuario tiene que elegir a conciencia.
    @Published var checkedOrphans: Set<String> = []
    /// Lo último que macOS no dejó quitar, para poder ofrecer abrirlo en el Finder.
    @Published private(set) var protectedPaths: [URL] = []
    /// La medición de tamaños, para poder abandonarla.
    ///
    /// Entrar en los datos de otras apps es cosa de macOS: pide permiso, y hasta que
    /// no se responde el proceso se queda esperando dentro de `open()`. Si eso pasa,
    /// esta tarea no vuelve nunca — así que al menos se abandona al volver a buscar,
    /// y lo que publique después se ignora.
    private var measuring: Task<Void, Never>?

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

    // MARK: - Restos de apps que ya no están

    /// Busca por la biblioteca archivos con nombre de identificador de app
    /// (`com.empresa.app`) que no correspondan a ninguna app instalada.
    ///
    /// Va en dos fases a propósito. En este Mac hay **1.247 candidatos**, 643 solo en
    /// `~/Library/Containers`, y medir el tamaño de cada uno recorriendo su árbol
    /// tardaba más de diez minutos: `du` sobre esa carpeta ni siquiera termina. Así
    /// que primero se enseña la lista (rápido, solo nombres) y los tamaños van
    /// llegando después, uno a uno, mientras el usuario ya está leyendo.
    func scanOrphans() {
        guard !scanningOrphans else { return }
        measuring?.cancel()
        scanningOrphans = true
        orphans = []
        checkedOrphans = []
        Task.detached(priority: .userInitiated) {
            // Fase 1: quiénes son. Sin abrir nada, solo leyendo nombres de carpeta.
            let found = Self.findOrphans()
            await MainActor.run {
                self.orphans = found
                self.scanningOrphans = false
                self.measuringOrphans = !found.isEmpty
                guard !found.isEmpty else { return }
                // Fase 2: cuánto ocupan, de uno en uno y publicando según llegan.
                self.measuring = Task.detached(priority: .utility) {
                    for orphan in found {
                        guard !Task.isCancelled else { return }
                        let size = orphan.urls.reduce(Int64(0)) { $0 + Self.boundedSize($1) }
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard let index = self.orphans.firstIndex(where: { $0.bundleID == orphan.bundleID })
                            else { return }
                            self.orphans[index].size = size
                        }
                    }
                    await MainActor.run {
                        self.orphans.sort { $0.size > $1.size }
                        self.measuringOrphans = false
                    }
                }
            }
        }
    }

    /// Los candidatos, sin medir nada.
    ///
    /// De los ~1.145 nombres con pinta de identificador que hay en la biblioteca de
    /// este Mac, la inmensa mayoría son del propio macOS. El filtro va en cuatro
    /// pasos, del más barato al más caro, y todos ellos descartan; ninguno añade.
    nonisolated private static func findOrphans() -> [OrphanLeftover] {
        let fm = FileManager.default
        var groups: [String: [URL]] = [:]
        // Solo dentro de la carpeta del usuario: fuera de ahí hay demasiadas cosas del
        // sistema con pinta de resto y el riesgo no compensa.
        for place in LeftoverPlace.all where place.inHome {
            guard let names = try? fm.contentsOfDirectory(atPath: place.url.path) else { continue }
            for name in names {
                guard let id = OrphanRules.bundleID(from: name) else { continue }
                groups[id, default: []].append(place.url.appending(path: name))
            }
        }

        let installedVendors = self.installedVendors()
        return groups.compactMap { id, urls -> OrphanLeftover? in
            // 1. Apple, aunque el identificador no lo diga (Atajos es «is.workflow»).
            guard !OrphanRules.isSystem(id) else { return nil }
            // 2. Marcos y actualizadores que viven dentro de otras apps.
            guard !OrphanRules.isSharedComponent(id) else { return nil }
            // 3. ¿Hay una app instalada de ese fabricante? Entonces esto es suyo.
            if let vendor = OrphanRules.vendor(of: id), installedVendors.contains(vendor) { return nil }
            // 4. Lo más caro: preguntarle a macOS por el identificador y por cada uno
            //    de sus prefijos, para que «com.empresa.app.ayudante» no salga si
            //    «com.empresa.app» sigue instalada donde sea.
            guard !isInstalled(id) else { return nil }
            return OrphanLeftover(bundleID: id, name: OrphanRules.displayName(for: id), urls: urls, size: 0)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Fabricantes con al menos una app instalada (`com.spotify`, `net.whatsapp`…).
    ///
    /// Hace falta porque a los contenedores de grupo no se llega por identificador:
    /// ninguna app se llama `net.whatsapp.family`, pero la carpeta es de WhatsApp.
    nonisolated private static func installedVendors() -> Set<String> {
        let fm = FileManager.default
        var vendors = Set<String>()
        // Las de sistema también cuentan: sus restos tampoco se tocan.
        let folders = appFolders + ["/System/Applications", "/System/Applications/Utilities"]
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let plist = folder + "/" + name + "/Contents/Info.plist"
                guard let info = NSDictionary(contentsOfFile: plist),
                      let id = info["CFBundleIdentifier"] as? String,
                      let vendor = OrphanRules.vendor(of: id) else { continue }
                vendors.insert(vendor)
            }
        }
        return vendors
    }

    /// ¿Conoce macOS una app con este identificador, o con alguno de sus prefijos?
    nonisolated private static func isInstalled(_ bundleID: String) -> Bool {
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) != nil {
                return true
            }
            parts.removeLast()
        }
        return false
    }

    /// Tamaño de una carpeta, dejando de contar si es enorme.
    ///
    /// Un contenedor puede tener cientos de miles de archivos y medirlo entero no
    /// aporta nada: lo que el usuario necesita saber es el orden de magnitud.
    nonisolated private static func boundedSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else {
            return CacheCleaner.directorySize(url)
        }
        var total: Int64 = 0
        var seen = 0
        for case let file as URL in enumerator {
            seen += 1
            if seen > 20_000 { break }
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    var checkedOrphanSize: Int64 {
        orphans.filter { checkedOrphans.contains($0.bundleID) }.reduce(0) { $0 + $1.size }
    }

    /// Manda a la papelera los restos huérfanos marcados.
    @discardableResult
    func trashCheckedOrphans() -> Int {
        let targets = orphans.filter { checkedOrphans.contains($0.bundleID) }
            .flatMap { orphan in orphan.urls.map { (url: $0, size: Int64(0)) } }
        // El tamaño va por resto, no por archivo: se reparte al final con lo que
        // haya salido bien.
        var outcome = Self.trash(targets)
        for orphan in orphans where checkedOrphans.contains(orphan.bundleID) {
            let moved = orphan.urls.allSatisfy { url in
                !outcome.protected.contains(url) && !outcome.failed.contains(url)
            }
            if moved { outcome.freed += orphan.size }
        }
        lastResult = Self.summary(outcome)
        protectedPaths = outcome.protected
        scanOrphans()
        return outcome.protected.count + outcome.failed.count
    }

    // MARK: - A la papelera

    /// Lo que pasó al intentar mover unas cuantas cosas.
    struct TrashOutcome {
        var freed: Int64 = 0
        /// Protegidas por macOS: no es cuestión de permisos, es que no se puede.
        var protected: [URL] = []
        /// Fallaron por otra cosa (permisos de administrador, normalmente).
        var failed: [URL] = []

        var allGood: Bool { protected.isEmpty && failed.isEmpty }
    }

    /// Manda a la papelera, contando solo lo que de verdad se movió.
    ///
    /// Antes se sumaba el tamaño **antes** de saber si la operación había ido bien,
    /// así que la app decía «liberados 30 MB» aunque no hubiera movido nada. Ahora el
    /// contador solo sube cuando el archivo ya está en la papelera.
    nonisolated static func trash(_ targets: [(url: URL, size: Int64)]) -> TrashOutcome {
        var outcome = TrashOutcome()
        for target in targets {
            do {
                try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
                outcome.freed += target.size
            } catch let error as NSError {
                if isSystemProtected(target.url, error: error) {
                    outcome.protected.append(target.url)
                } else {
                    outcome.failed.append(target.url)
                }
            }
        }
        return outcome
    }

    /// ¿Es de las que macOS no deja tocar a nadie?
    ///
    /// Se mira la ruta **y** el error: así no se confunde un contenedor de verdad
    /// con un fallo de permisos que sí se arregla con la contraseña.
    nonisolated static func isSystemProtected(_ url: URL, error: NSError) -> Bool {
        error.code == NSFileWriteNoPermissionError && url.path.contains("/Library/Containers")
            || error.code == NSFileWriteNoPermissionError && url.path.contains("/Library/Group Containers")
    }

    /// Cómo contarlo en una frase.
    nonisolated static func summary(_ outcome: TrashOutcome) -> String {
        var parts = [L("A la papelera: \(CacheCleaner.format(outcome.freed))",
                       "Moved to Trash: \(CacheCleaner.format(outcome.freed))")]
        if !outcome.protected.isEmpty {
            parts.append(L("\(outcome.protected.count) contenedor(es) los protege macOS: solo el Finder puede quitarlos.",
                           "\(outcome.protected.count) container(s) are protected by macOS: only Finder can remove them."))
        }
        if !outcome.failed.isEmpty {
            parts.append(L("\(outcome.failed.count) sin permiso (pide contraseña de administrador).",
                           "\(outcome.failed.count) needed an administrator password."))
        }
        return parts.joined(separator: " ")
    }

    /// Manda a la papelera lo marcado. Devuelve cuántos elementos no pudo mover.
    @discardableResult
    func trashChecked() -> Int {
        // Los restos primero y la app al final: si algo falla, no dejamos una app a
        // medio desinstalar sin sus datos.
        var targets: [(url: URL, size: Int64)] = leftovers.filter { checked.contains($0.url) }
            .map { (url: $0.url, size: $0.size) }
        var trashedApp = false
        if let selected, checked.contains(selected.url) {
            targets.append((url: selected.url, size: selected.size))
            trashedApp = true
        }

        let outcome = Self.trash(targets)
        lastResult = Self.summary(outcome)
        protectedPaths = outcome.protected

        if trashedApp, outcome.allGood {
            clearSelection()
            loadApps()
        } else if let selected {
            select(selected)   // volver a mirar qué queda
        }
        return outcome.protected.count + outcome.failed.count
    }

    /// Abre en el Finder lo que macOS no deja quitar, ya seleccionado.
    func revealProtected() {
        guard !protectedPaths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(protectedPaths)
    }
}
