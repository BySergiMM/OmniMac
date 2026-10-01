import AppKit

/// Instala las apps que descargas en `.dmg`, sin el baile de siempre.
///
/// El baile: doble clic en el .dmg, esperar, arrastrar el icono a la carpeta
/// Aplicaciones, expulsar el disco, y acordarse de tirar el .dmg. Cuatro pasos que
/// siempre son los mismos.
///
/// Reglas que se ha impuesto esto, porque toca archivos ajenos:
///
/// - **Nunca hace nada sin preguntar.** Aparece un aviso con el nombre de la app y
///   ahí decides.
/// - **Espera a que la descarga acabe**: si el tamaño del archivo sigue creciendo,
///   ni se mira.
/// - **Nada se borra**: el .dmg acaba en la papelera, de donde se recupera.
/// - **Si hay algo raro dentro, se rinde**: un .dmg con un instalador `.pkg`, con
///   varias apps o sin ninguna se deja en paz y lo abre como habrías hecho tú.
/// - **Enseña quién firmó la app antes de copiarla** (su Team ID) y avisa si no es el
///   mismo que el de la que ya tienes, o si no hay firma de la que fiarse. Ver
///   `InstallReview`.
/// - **Nunca quita la marca de «descargado de Internet»**: la copia queda con la del
///   .dmg, para que Gatekeeper la revise al abrirla. Ver `QuarantineMark`.
enum DiskImageRules {

    /// ¿Merece la pena mirar este archivo?
    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        // `.dmg.download` de Safari, `.crdownload` de Chrome, `.part`… todavía no.
        guard lower.hasSuffix(".dmg"), !lower.hasPrefix(".") else { return false }
        return true
    }

    /// Elige la app de dentro del disco montado.
    ///
    /// Solo si hay **exactamente una**. Con dos o más no hay forma de acertar sin
    /// preguntar, y preguntar por cada una convierte el atajo en un incordio.
    static func appToInstall(in contents: [String]) -> String? {
        let apps = contents.filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }
        // Un `.pkg` dentro quiere decir que hay un instalador de verdad, con sus
        // pasos y sus permisos: eso no se automatiza.
        guard !contents.contains(where: { $0.lowercased().hasSuffix(".pkg") }) else { return nil }
        return apps.count == 1 ? apps[0] : nil
    }

    /// Dónde va la app.
    ///
    /// `/Applications` si se puede escribir; si no, la carpeta Aplicaciones del
    /// usuario, que no pide contraseña. Mejor instalarla en un sitio razonable que
    /// pedir permisos de administrador.
    static func destination(canWriteToApplications: Bool, home: String) -> String {
        canWriteToApplications ? "/Applications" : home + "/Applications"
    }
}

/// Lo que se ve al montar el disco: lo que se le enseña al usuario antes de copiar nada.
struct DiskImageInspection {
    /// «Ice.app»
    let appName: String
    /// Quién firmó la app que trae el disco.
    let incoming: AppSigner
    /// Quién firmó la que ya hay en el destino. `nil` si no hay ninguna.
    let installed: AppSigner?
    /// La carpeta donde se copiaría.
    let folder: String

    /// «Ice»
    var displayName: String { String(appName.dropLast(4)) }
}

/// Vigila la carpeta de Descargas y ofrece instalar lo que llega.
///
/// Son dos avisos seguidos, y es a propósito. El primero pide permiso para montar el disco,
/// que es lo mínimo que se necesita para poder mirar quién firmó la app: sin él se montaría
/// cualquier .dmg que cayera en Descargas sin que nadie lo hubiera pedido. El segundo ya
/// enseña el Team ID y es el que decide.
@MainActor
final class DiskImageInstaller {
    static let shared = DiskImageInstaller()

    /// Cada cuánto se mira la carpeta. No hace falta más: nadie descarga una app y
    /// espera que se instale en el mismo segundo.
    private static let interval: TimeInterval = 8

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "tools.dmgInstaller") }
        set {
            UserDefaults.standard.set(newValue, forKey: "tools.dmgInstaller")
            newValue ? start() : stop()
        }
    }

    private var timer: Timer?
    /// Lo ya visto, para no volver a preguntar por lo mismo.
    private var seen: Set<String> = []
    /// Tamaños de la vuelta anterior: si no ha cambiado, la descarga terminó.
    private var sizes: [String: Int] = [:]
    private var busy = false

    private var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
    }

    private init() {}

    func startIfEnabled() { if enabled { start() } }

    private func start() {
        guard timer == nil else { return }
        // Lo que ya está descargado al arrancar no se toca: solo interesa lo nuevo.
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? [])
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        t.tolerance = Self.interval / 2
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        seen = []
        sizes = [:]
    }

    private func scan() {
        guard !busy,
              let names = try? FileManager.default.contentsOfDirectory(atPath: downloads.path) else { return }
        for name in names where DiskImageRules.isCandidate(name) && !seen.contains(name) {
            let path = downloads.appending(path: name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            // Dos vueltas con el mismo tamaño = la descarga ha terminado.
            guard let previous = sizes[name], previous == size, size > 0 else {
                sizes[name] = size
                continue
            }
            sizes[name] = nil
            seen.insert(name)
            offer(URL(fileURLWithPath: path))
            return   // de una en una: dos avisos a la vez es una encerrona
        }
    }

    // MARK: - Primer aviso: ¿puedo mirar el disco?

    private func offer(_ image: URL) {
        let alert = NSAlert()
        alert.messageText = L("¿Instalo \(image.lastPathComponent)?",
                              "Install \(image.lastPathComponent)?")
        alert.informativeText = L("OmniMac puede montar el disco, comprobar quién firmó la app, copiarla a Aplicaciones, expulsarlo y mandar el .dmg a la papelera. Antes de copiar nada te enseña quién la firmó y te vuelve a preguntar.",
                                  "OmniMac can mount the image, check who signed the app, copy it to Applications, eject it and move the .dmg to the Trash. Before copying anything it shows you who signed it and asks you again.")
        alert.addButton(withTitle: L("Revisar", "Check it"))
        alert.addButton(withTitle: L("Ahora no", "Not now"))
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        inspect(image)
    }

    private func inspect(_ image: URL) {
        busy = true
        Toast.show(L("Revisando la app…", "Checking the app…"), symbol: "magnifyingglass", duration: 3)
        Task.detached(priority: .userInitiated) {
            let result = Self.inspectImage(image)
            await MainActor.run {
                switch result {
                case .ready(let inspection):
                    self.review(image, inspection)
                case .failure(let reason):
                    self.fail(reason, image: image)
                }
            }
        }
    }

    /// Si no se pudo, se abre el disco como habrías hecho tú.
    private func fail(_ reason: String, image: URL) {
        busy = false
        Toast.show(reason, symbol: "exclamationmark.triangle.fill")
        NSWorkspace.shared.open(image)
    }

    // MARK: - Segundo aviso: quién la firmó

    private func review(_ image: URL, _ inspection: DiskImageInspection) {
        let spanish = Localization.isSpanish
        let app = inspection.displayName
        let verdict = InstallReview.verdict(incoming: inspection.incoming, installed: inspection.installed)
        let buttons = InstallReview.buttons(for: verdict, spanish: spanish)

        let alert = NSAlert()
        alert.messageText = InstallReview.title(app: app, verdict: verdict, spanish: spanish)
        alert.informativeText = InstallReview.message(app: app, verdict: verdict,
                                                      folder: inspection.folder, spanish: spanish)
        alert.alertStyle = verdict.severity == .fine ? .informational : .warning
        for title in buttons.titles { alert.addButton(withTitle: title) }
        if buttons.installIndex == 0 && buttons.titles.count == 2 {
            // Con el botón de instalar por defecto, Esc cancela. Con un aviso el botón por
            // defecto es el de no instalar, y a ese le quedaría sin Intro.
            alert.buttons[1].keyEquivalent = "\u{1b}"
        }
        NSApp.activate(ignoringOtherApps: true)
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard index == buttons.installIndex else {
            // Cancelar, o una firma rota que no se instala: el .dmg se queda donde está.
            busy = false
            return
        }
        install(image, inspection)
    }

    private func install(_ image: URL, _ inspection: DiskImageInspection) {
        let name = image.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result = Self.performInstall(image, reviewed: inspection)
            await MainActor.run {
                self.busy = false
                switch result {
                case .success(let app):
                    Notifier.post(title: L("\(app) instalada", "\(app) installed"),
                                  body: L("El .dmg está en la papelera.", "The .dmg is in the Trash."),
                                  identifier: "dmg.\(name)")
                case .failure(let reason):
                    Toast.show(reason, symbol: "exclamationmark.triangle.fill")
                    // Si no se pudo, se abre como habrías hecho tú.
                    NSWorkspace.shared.open(image)
                }
            }
        }
    }

    // MARK: - Fuera del hilo principal

    private enum Inspected {
        case ready(DiskImageInspection)
        case failure(String)
    }

    private enum InstallResult {
        case success(String)
        case failure(String)
    }

    /// Monta el disco, mira qué app trae y quién la firmó (y quién firmó la que ya hay), y lo
    /// expulsa. No copia nada.
    nonisolated private static func inspectImage(_ image: URL) -> Inspected {
        let inspected = withMountedImage(image) { mount -> Inspected in
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mount.path),
                  let appName = DiskImageRules.appToInstall(in: contents) else {
                return .failure(L("Este disco no trae una sola app: lo abro para que lo mires.",
                                  "This image doesn't hold a single app: opening it for you."))
            }
            let folder = destinationFolder()
            let target = URL(fileURLWithPath: folder).appending(path: appName)
            var installed: AppSigner?
            if FileManager.default.fileExists(atPath: target.path) {
                installed = CodeSignature.signer(of: target)
            }
            let incoming = CodeSignature.signer(of: mount.appending(path: appName))
            return .ready(DiskImageInspection(appName: appName, incoming: incoming,
                                              installed: installed, folder: folder))
        }
        return inspected ?? .failure(L("No se pudo abrir el disco.", "Couldn't open the image."))
    }

    /// Vuelve a montar el disco, copia lo que se revisó y manda el .dmg a la papelera.
    nonisolated private static func performInstall(_ image: URL, reviewed: DiskImageInspection) -> InstallResult {
        let outcome = withMountedImage(image) { mount -> InstallResult in
            // El .dmg está en Descargas y ahí puede escribir cualquiera: pudo cambiar entre
            // que se revisó y ahora. Solo se instala lo que se le enseñó al usuario.
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mount.path),
                  DiskImageRules.appToInstall(in: contents) == reviewed.appName else {
                return .failure(L("El disco ha cambiado desde que se revisó: no se instala nada.",
                                  "The image changed after it was checked: nothing was installed."))
            }
            let folder = URL(fileURLWithPath: reviewed.folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let result = AppInstall.install(source: mount.appending(path: reviewed.appName),
                                            into: folder,
                                            expecting: reviewed.incoming,
                                            imageQuarantine: QuarantineAttribute.read(at: image),
                                            using: .live)
            switch result {
            case .success:
                return .success(reviewed.displayName)
            case .failure(let failure):
                return .failure(text(for: failure))
            }
        }
        guard let result = outcome else {
            return .failure(L("No se pudo abrir el disco.", "Couldn't open the image."))
        }
        // El .dmg a la papelera, nunca borrado. Solo si se instaló.
        if case .success = result {
            try? FileManager.default.trashItem(at: image, resultingItemURL: nil)
        }
        return result
    }

    nonisolated private static func text(for failure: AppInstall.Failure) -> String {
        switch failure {
        case .copyFailed(let why):
            return L("No se pudo copiar la app: \(why)", "Couldn't copy the app: \(why)")
        case .signerChanged:
            return L("La copia no lleva la firma que se revisó: no se instala nada.",
                     "The copy doesn't carry the signature that was checked: nothing was installed.")
        case .quarantineNotApplied:
            return L("No se pudo conservar la marca de «descargado de Internet»: no se instala nada.",
                     "Couldn't keep the “downloaded from the Internet” mark: nothing was installed.")
        case .replaceFailed(let why):
            return L("No se pudo colocar la app: \(why)", "Couldn't put the app in place: \(why)")
        }
    }

    /// `/Applications` si se puede escribir; si no, la del usuario.
    nonisolated private static func destinationFolder() -> String {
        let canWrite = FileManager.default.isWritableFile(atPath: "/Applications")
        return DiskImageRules.destination(canWriteToApplications: canWrite, home: NSHomeDirectory())
    }

    /// Monta el disco en una carpeta temporal, ejecuta `body` con ella y lo expulsa. `nil`
    /// si no se pudo montar.
    nonisolated private static func withMountedImage<T>(_ image: URL, _ body: (URL) -> T) -> T? {
        let mount = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "omnimac-dmg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mount) }

        // `-nobrowse` para que no salga en el Finder, y sin autoabrir nada.
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly",
                                       "-mountpoint", mount.path, "-quiet"]) == 0 else {
            return nil
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        return body(mount)
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
