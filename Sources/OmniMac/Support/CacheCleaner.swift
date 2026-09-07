import AppKit
import Combine

/// Caché de OmniMac en disco y su limpieza.
///
/// Qué hay en `~/Library/Caches/com.seergiii.omnimac`:
///   - `Cache.db` + `fsCachedData/`: la caché web del sistema (`URLCache`), donde van las
///     carátulas de Spotify que descarga el notch. Cada carátula son 100–300 KB y se
///     vuelve a descargar si hace falta.
///   - `org.sparkle-project.Sparkle/`: paquetes de actualización descargados y copias del
///     instalador que Sparkle deja tras actualizar (unos 10 MB por versión).
/// Nada de esto es necesario para que la app funcione: se regenera solo. Aquí se mide,
/// se limpia a mano desde Ajustes › Inicio y se limpia automáticamente una vez al día.
///
/// Coste en reposo: cero. La limpieza automática es un único temporizador de un solo
/// disparo con una hora de tolerancia; el tamaño solo se calcula con Ajustes abierto.
final class CacheCleaner: ObservableObject {
    static let shared = CacheCleaner()

    static let automaticKey = "cache.autoClean"
    static let lastCleanKey = "cache.lastClean"
    static let lastFreedKey = "cache.lastFreed"
    /// Cada cuánto limpia sola.
    static let interval: TimeInterval = 24 * 60 * 60
    /// Tope de la caché web (carátulas). Aunque la limpieza fallara, nunca pasa de aquí.
    static let webCacheDiskLimit = 16 << 20   // 16 MB
    static let webCacheMemoryLimit = 4 << 20  // 4 MB

    /// Bytes que ocupa ahora la caché (se actualiza con `refresh()` y tras limpiar).
    @Published private(set) var cacheSize: Int64 = 0
    /// Bytes que ocupa la app instalada (binario, Sparkle y recursos).
    @Published private(set) var appSize: Int64 = 0
    /// Limpieza automática diaria (por defecto activada).
    @Published var automatic: Bool {
        didSet {
            UserDefaults.standard.set(automatic, forKey: Self.automaticKey)
            schedule()
        }
    }

    var lastClean: Date? { UserDefaults.standard.object(forKey: Self.lastCleanKey) as? Date }
    var lastFreed: Int64? {
        UserDefaults.standard.object(forKey: Self.lastFreedKey) == nil ? nil : Int64(UserDefaults.standard.integer(forKey: Self.lastFreedKey))
    }

    private var timer: Timer?
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.seergiii.omnimac"

    /// `~/Library/Caches/<bundle>`: la carpeta de caché que macOS reserva a esta app.
    var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true)
    }

    private init() {
        let defaults = UserDefaults.standard
        automatic = defaults.object(forKey: Self.automaticKey) == nil ? true : defaults.bool(forKey: Self.automaticKey)
        // Caché web acotada: la de serie no tiene un tope tan bajo y las carátulas se acumulaban.
        URLCache.shared = URLCache(memoryCapacity: Self.webCacheMemoryLimit, diskCapacity: Self.webCacheDiskLimit, directory: cacheDirectory)
    }

    // MARK: - Medir

    /// Recalcula los tamaños en segundo plano (es lo único que cuesta algo: recorrer ~150 archivos).
    func refresh() {
        let cacheURL = cacheDirectory
        let appURL = Bundle.main.bundleURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cache = Self.directorySize(cacheURL)
            let app = Self.directorySize(appURL)
            DispatchQueue.main.async {
                self?.cacheSize = cache
                self?.appSize = app
            }
        }
    }

    /// Suma del tamaño de todos los archivos bajo `url` (0 si no existe).
    static func directorySize(_ url: URL) -> Int64 {
        // También vale para un archivo suelto (un .plist de preferencias, por
        // ejemplo): el enumerador solo recorre carpetas y devolvía cero.
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// «12,3 MB», en el idioma del Mac.
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Limpiar

    /// Limpia todo lo prescindible y devuelve los bytes liberados. Se puede llamar desde
    /// cualquier hilo; `updating` dice si Sparkle está a medias (entonces no toca su carpeta).
    @discardableResult
    func clean(updating: Bool) -> Int64 {
        let directory = cacheDirectory
        let before = Self.directorySize(directory)
        let manager = FileManager.default

        // 1. Caché web: vacía la base de datos y borra los archivos de las respuestas.
        URLCache.shared.removeAllCachedResponses()
        let orphans = directory.appendingPathComponent("fsCachedData", isDirectory: true)
        if let files = try? manager.contentsOfDirectory(at: orphans, includingPropertiesForKeys: nil) {
            files.forEach { try? manager.removeItem(at: $0) }
        }
        // 2. Restos de Sparkle (descargas e instaladores ya usados). Los vuelve a crear cuando
        //    haga falta; solo se respeta si hay una actualización en marcha.
        if !updating {
            try? manager.removeItem(at: directory.appendingPathComponent("org.sparkle-project.Sparkle", isDirectory: true))
        }

        let after = Self.directorySize(directory)
        let freed = max(0, before - after)
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Self.lastCleanKey)
        defaults.set(Int(freed), forKey: Self.lastFreedKey)
        DispatchQueue.main.async { [weak self] in
            self?.cacheSize = after
            self?.objectWillChange.send()
        }
        return freed
    }

    /// Botón «Limpiar ahora» de Ajustes: limpia, avisa con cuánto ha liberado y recalcula.
    func cleanNow() {
        let updating = UpdaterController.shared.sessionInProgress
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let freed = self.clean(updating: updating)
            DispatchQueue.main.async {
                Toast.show(freed == 0 ? L("La caché ya estaba vacía", "The cache was already empty")
                                      : L("Caché limpiada · \(Self.format(freed)) liberados", "Cache cleaned · \(Self.format(freed)) freed"),
                           symbol: "trash")
                self.refresh()
            }
        }
    }

    // MARK: - Automática

    /// Arranque: programa la limpieza diaria si está activada. Nunca en los primeros 60 s.
    func startAutomaticCleaning() {
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard automatic else { return }
        let due = (lastClean ?? .distantPast).addingTimeInterval(Self.interval)
        let delay = max(60, due.timeIntervalSinceNow)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.runAutomatic()
        }
        t.tolerance = min(3600, max(60, delay * 0.1))   // macOS puede agrupar el despertar
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func runAutomatic() {
        let updating = UpdaterController.shared.sessionInProgress
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.clean(updating: updating)
            DispatchQueue.main.async { self.schedule() }   // siguiente: dentro de 24 h
        }
    }

    // MARK: - Texto para Ajustes

    var statusText: String {
        var parts = [L("Carátulas descargadas y restos de actualizaciones: \(Self.format(cacheSize)).", "Downloaded artwork and update leftovers: \(Self.format(cacheSize)).")]
        if let lastClean {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: Localization.isSpanish ? "es_ES" : "en_US")
            let when = formatter.localizedString(for: lastClean, relativeTo: Date())
            let freed = lastFreed.map { Self.format($0) } ?? "0 KB"
            parts.append(L("Última limpieza \(when): \(freed) liberados.", "Last cleaned \(when): \(freed) freed."))
        } else {
            parts.append(L("Aún no se ha limpiado.", "Not cleaned yet."))
        }
        return parts.joined(separator: " ")
    }
}
