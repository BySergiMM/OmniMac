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

/// Vigila la carpeta de Descargas y ofrece instalar lo que llega.
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

    private func offer(_ image: URL) {
        let alert = NSAlert()
        alert.messageText = L("¿Instalo \(image.lastPathComponent)?",
                              "Install \(image.lastPathComponent)?")
        alert.informativeText = L("OmniMac puede montar el disco, copiar la app a Aplicaciones, expulsarlo y mandar el .dmg a la papelera.",
                                  "OmniMac can mount the image, copy the app to Applications, eject it and move the .dmg to the Trash.")
        alert.addButton(withTitle: L("Instalar", "Install"))
        alert.addButton(withTitle: L("Ahora no", "Not now"))
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(image)
    }

    private func install(_ image: URL) {
        busy = true
        let name = image.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result = Self.performInstall(image)
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

    private enum InstallResult {
        case success(String)
        case failure(String)
    }

    /// Monta, copia, expulsa y tira el .dmg. Fuera del hilo principal.
    nonisolated private static func performInstall(_ image: URL) -> InstallResult {
        let mount = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "omnimac-dmg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mount) }

        // `-nobrowse` para que no salga en el Finder, y sin autoabrir nada.
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly",
                                       "-mountpoint", mount.path, "-quiet"]) == 0 else {
            return .failure(L("No se pudo abrir el disco.", "Couldn't open the image."))
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mount.path),
              let appName = DiskImageRules.appToInstall(in: contents) else {
            return .failure(L("Este disco no trae una sola app: lo abro para que lo mires.",
                              "This image doesn't hold a single app: opening it for you."))
        }

        let applications = "/Applications"
        let canWrite = FileManager.default.isWritableFile(atPath: applications)
        let folder = DiskImageRules.destination(canWriteToApplications: canWrite, home: NSHomeDirectory())
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

        let source = mount.appending(path: appName)
        let target = URL(fileURLWithPath: folder).appending(path: appName)
        // Si ya estaba, la anterior va a la papelera: es una actualización, y así se
        // puede volver atrás.
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.trashItem(at: target, resultingItemURL: nil)
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            return .failure(L("No se pudo copiar la app: \(error.localizedDescription)",
                              "Couldn't copy the app: \(error.localizedDescription)"))
        }
        // El .dmg a la papelera, nunca borrado.
        try? FileManager.default.trashItem(at: image, resultingItemURL: nil)
        return .success(String(appName.dropLast(4)))
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
