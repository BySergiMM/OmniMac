import AppKit
import Carbon.HIToolbox
import Combine

/// Módulo Portapapeles: vigila lo que copias y guarda el historial (texto, imágenes y archivos).
struct ClipItem: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(NSImage)
        case files([URL])
    }

    let id: UUID
    let content: Content
    let date: Date
    /// Anclado: siempre arriba, nunca se descarta y se guarda aunque el historial no.
    var pinned = false
    /// El texto venía tan largo que hubo que recortarlo. El panel lo dice: pegar
    /// media página y que falte el resto sin avisar es peor que no guardarlo.
    var truncated = false

    init(id: UUID = UUID(), content: Content, date: Date = Date(),
         pinned: Bool = false, truncated: Bool = false) {
        self.id = id
        self.content = content
        self.date = date
        self.pinned = pinned
        self.truncated = truncated
    }

    /// Texto para mostrar y buscar.
    var text: String {
        switch content {
        case .text(let string): string
        case .image(let image): L("Imagen · \(Int(image.size.width)) × \(Int(image.size.height))", "Image · \(Int(image.size.width)) × \(Int(image.size.height))")
        case .files(let urls): urls.map(\.lastPathComponent).joined(separator: ", ")
        }
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
}

/// Una app de la lista de exclusión, con lo justo para pintarla en Ajustes.
///
/// Solo se guarda el identificador, que no cambia aunque muevan la app de carpeta o
/// la renombren; el nombre y el icono se buscan al dibujar. Si la app ya no está
/// instalada queda el identificador a secas, que al menos dice de quién se trataba.
struct ExcludedApp: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?

    var id: String { bundleID }

    init(bundleID: String) {
        self.bundleID = bundleID
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        // El nombre traducido, que es el que la persona ve en el Finder: «Acceso a
        // Llaveros», no «Keychain Access». Si tiene puesto ver las extensiones,
        // `displayName` devuelve el «.app» y sobra.
        name = url.map { url in
            let shown = FileManager.default.displayName(atPath: url.path)
            return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        } ?? bundleID
        icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Historial del portapapeles: texto, imágenes y archivos. ⇧⌘V abre el panel;
/// escribe para buscar; al elegir un elemento se copia y se pega automáticamente.
/// Por privacidad vive en memoria salvo que actives «Guardar en disco».
final class ClipboardFeature: BaseFeature {
    @Published private(set) var items: [ClipItem] = [] {
        didSet { scheduleSave() }
    }

    @Published var maxItems: Int {
        didSet {
            UserDefaults.standard.set(maxItems, forKey: "clipboard.maxItems")
            trim()
        }
    }

    /// Guardar el historial en disco (Application Support) para conservarlo entre sesiones.
    @Published var persist: Bool {
        didSet {
            UserDefaults.standard.set(persist, forKey: "clipboard.persist")
            if persist { saveNow() } else { deleteStore() }
        }
    }

    /// Ignorar lo que se copie mientras esté pausado (datos sensibles, etc.).
    @Published var paused = false

    /// Apps de las que nunca se guarda nada (identificadores de paquete).
    ///
    /// La pausa es de todo o nada y hay que acordarse de encenderla; esto es para lo
    /// que uno no quiere guardar nunca, sin pensarlo: el gestor de contraseñas, la
    /// app del banco, el trabajo. Quién decide, en `ClipboardFilter`.
    @Published var excludedApps: [String] {
        didSet {
            UserDefaults.standard.set(excludedApps, forKey: "clipboard.excludedApps")
            rebuildExclusions()
        }
    }

    /// Sumar a esa lista los gestores de contraseñas conocidos (encendido de fábrica).
    ///
    /// Es un interruptor y no una copia de los identificadores en la lista del
    /// usuario a propósito: así el gestor que se instale mañana queda cubierto sin
    /// tener que volver a Ajustes. Ajustes enseña cuáles cubre de verdad en este Mac.
    @Published var ignoreKnownPasswordManagers: Bool {
        didSet {
            UserDefaults.standard.set(ignoreKnownPasswordManagers, forKey: "clipboard.ignoreManagers")
            rebuildExclusions()
        }
    }

    /// La lista ya montada y normalizada: se rehace al cambiarla, no en cada copia.
    private var exclusions: Set<String> = []

    /// Quitar el rastreo de los enlaces nada más copiarlos.
    ///
    /// Va apagado por defecto: reescribir lo que alguien acaba de copiar es
    /// atrevido, y quien lo quiera lo enciende sabiendo lo que hace.
    @Published var cleanURLs: Bool {
        didSet { UserDefaults.standard.set(cleanURLs, forKey: "clipboard.cleanURLs") }
    }

    /// Pegar sin formato con ⌥⇧⌘V.
    ///
    /// Copiar de una web y pegar en un documento se trae la tipografía, el tamaño y
    /// los colores de la web. Esto pega solo el texto, dejando el formato del sitio
    /// donde pegas. No toca el historial: actúa sobre lo que haya en el portapapeles
    /// en ese momento, venga de donde venga.
    @Published var plainPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(plainPasteEnabled, forKey: "clipboard.plainPaste")
            guard isEnabled else { return }
            if plainPasteEnabled { registerPlainPaste() } else { HotKeyCenter.shared.unbind(Self.plainShortcut) }
        }
    }

    /// Cada cuánto se mira el portapapeles en reposo. Con tolerancia, el sistema
    /// agrupa los despertares y el módulo no se nota en el consumo.
    private static let idleInterval: TimeInterval = 1.0
    /// Y cada cuánto mientras se está copiando.
    private static let busyInterval: TimeInterval = 0.25
    /// Cuánto se sigue mirando deprisa desde la última copia.
    private static let busyWindow: TimeInterval = 4.0

    /// Cada cuánto hay que mirar, según cuánto hace que se copió algo.
    ///
    /// Con una sola mirada por segundo, copiar dos cosas seguidas perdía la primera
    /// sin dejar rastro: `changeCount` salta de 5 a 7 y lo que hubiera en la 5 ya no
    /// existe. En cuanto se copia algo se mira cuatro veces por segundo unos
    /// segundos, y después se vuelve a la calma: **en reposo se mira exactamente
    /// igual que antes**, que es lo que cuentan las cifras de consumo.
    static func pollInterval(sinceLastChange seconds: TimeInterval) -> TimeInterval {
        seconds < busyWindow ? busyInterval : idleInterval
    }

    private var timer: Timer?
    private var currentInterval: TimeInterval = ClipboardFeature.idleInterval
    /// Cuándo se vio por última vez algo nuevo en el portapapeles.
    private var lastChangeAt = Date.distantPast
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let panel = ClipboardPanelController()
    private var previousApp: NSRunningApplication?
    private var saveWork: DispatchWorkItem?
    /// La app que estaba delante la última vez que se miró el portapapeles.
    private var frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    /// La última app de delante que no era OmniMac: a esa hay que volver para pegar.
    ///
    /// Con ⇧⌘V la app de delante es la de la persona, pero el historial también se
    /// abre desde el icono de la barra y desde la barra de comandos, y entonces
    /// delante estamos nosotros: sin esto, al elegir un elemento se activaba OmniMac
    /// y el ⌘V se lo comía él. Quedaba copiado, pero no se pegaba en ningún sitio.
    private var lastForeignApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var installedManagers: [ExcludedApp]?

    /// A partir de aquí, un texto copiado se recorta (y se dice que se ha recortado).
    static let maxTextLength = 20_000

    /// Los atajos del módulo. Se pueden cambiar en Ajustes; estos son los de fábrica.
    static let historyShortcut = ShortcutBinding(key: "clipboard.history", hotKeyID: 200,
                                                 title: L("Abrir el historial del portapapeles", "Open the clipboard history"),
                                                 fallback: Shortcut(kVK_ANSI_V, cmdKey | shiftKey))
    static let plainShortcut = ShortcutBinding(key: "clipboard.pastePlain", hotKeyID: 201,
                                               title: L("Pegar sin formato", "Paste as plain text"),
                                               fallback: Shortcut(kVK_ANSI_V, cmdKey | shiftKey | optionKey))

    init() {
        let stored = UserDefaults.standard.integer(forKey: "clipboard.maxItems")
        maxItems = stored == 0 ? 40 : stored
        plainPasteEnabled = UserDefaults.standard.object(forKey: "clipboard.plainPaste") == nil
            ? true : UserDefaults.standard.bool(forKey: "clipboard.plainPaste")
        cleanURLs = UserDefaults.standard.bool(forKey: "clipboard.cleanURLs")
        persist = UserDefaults.standard.bool(forKey: "clipboard.persist")
        excludedApps = UserDefaults.standard.stringArray(forKey: "clipboard.excludedApps") ?? []
        ignoreKnownPasswordManagers = UserDefaults.standard.object(forKey: "clipboard.ignoreManagers") == nil
            ? true : UserDefaults.standard.bool(forKey: "clipboard.ignoreManagers")
        super.init(id: "clipboard",
                   name: L("Historial del portapapeles", "Clipboard history"),
                   symbol: "doc.on.clipboard",
                   blurb: L("Guarda lo que copias (texto, imágenes y archivos) y pégalo cuando quieras con ⇧⌘V.", "Saves what you copy (text, images and files) and pastes it whenever you want with ⇧⌘V."),
                   defaultEnabled: true)

        panel.onSelect = { [weak self] item in self?.paste(item) }
        panel.onDelete = { [weak self] item in self?.remove(item) }
        panel.onPin = { [weak self] item in self?.togglePin(item) }
        rebuildExclusions() // los `didSet` no corren en el init
        load()
    }

    /// Ancla o desancla un elemento (⌥P en el panel).
    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        sortItems()
        panel.update(items: items)
    }

    /// Anclados primero (por fecha), después el resto (por fecha).
    private func sortItems() {
        items = items.filter(\.pinned).sorted { $0.date > $1.date }
            + items.filter { !$0.pinned }.sorted { $0.date > $1.date }
    }

    override func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        rememberForeignApp(NSWorkspace.shared.frontmostApplication)
        // Al cambiar de app se mira el portapapeles antes de dar por buena la nueva.
        // Con un sondeo por segundo, copiar la contraseña y saltar al navegador en
        // menos de un segundo haría que lo copiado pareciese copiado por el navegador
        // —y se guardaría—. Lo que esté pendiente al cambiar es de la app que se deja.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.poll(attributingTo: self.frontApp)
                let front = NSWorkspace.shared.frontmostApplication
                self.frontApp = front?.bundleIdentifier
                self.rememberForeignApp(front)
            }
        lastChangeAt = .distantPast
        startTimer(every: Self.idleInterval)
        HotKeyCenter.shared.bind(Self.historyShortcut) { [weak self] in self?.togglePanel() }
        if plainPasteEnabled { registerPlainPaste() }
    }

    /// El temporizador del sondeo. Se rehace al cambiar de ritmo.
    private func startTimer(every interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = interval * 0.3
        timer = t
        currentInterval = interval
    }

    private func tick() {
        poll()
        let wanted = Self.pollInterval(sinceLastChange: Date().timeIntervalSince(lastChangeAt))
        guard wanted != currentInterval else { return }
        startTimer(every: wanted)
    }

    private func registerPlainPaste() {
        HotKeyCenter.shared.bind(Self.plainShortcut) { [weak self] in self?.pastePlain() }
    }

    /// Limpia el enlace que haya ahora en el portapapeles, sin pegar nada.
    @discardableResult
    func cleanClipboardURL() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              let cleaned = URLCleaner.clean(text) else {
            Toast.show(L("No hay ningún enlace con rastreo", "No tracked link to clean"), symbol: "link")
            return false
        }
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
        lastChangeCount = pasteboard.changeCount
        Toast.show(L("Enlace limpio de rastreo", "Tracking removed from the link"), symbol: "link")
        return true
    }

    /// Deja en el portapapeles solo el texto y pega.
    ///
    /// Se lee con `.string`, que es lo que da AppKit ya convertido a texto plano
    /// aunque el original fuera RTF o HTML. Si lo que hay no es texto (una imagen,
    /// unos archivos) no se toca nada: mejor no hacer nada que vaciarle el
    /// portapapeles a alguien.
    func pastePlain() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        guard Permissions.hasAccessibility else {
            Toast.show(L("Sin formato, listo para pegar", "Formatting removed, ready to paste"),
                       symbol: "doc.on.clipboard")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.sendCmdV() }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        HotKeyCenter.shared.unbind(Self.historyShortcut)
        HotKeyCenter.shared.unbind(Self.plainShortcut)
        panel.hide()
    }

    /// Vacía el historial; los anclados se quedan.
    func clear() {
        items.removeAll { !$0.pinned }
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    func togglePanel() {
        if panel.isVisible {
            panel.hide()
            return
        }
        poll() // por si copiaste algo hace menos de un segundo
        let front = NSWorkspace.shared.frontmostApplication
        // Si el historial se abre desde el menú de la barra o la barra de comandos,
        // delante está OmniMac: hay que volver a la app anterior, no a nosotros.
        previousApp = isOurs(front) ? lastForeignApp : front
        panel.show(items: items)
    }

    private func isOurs(_ app: NSRunningApplication?) -> Bool {
        app?.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    private func rememberForeignApp(_ app: NSRunningApplication?) {
        guard let app, !isOurs(app) else { return }
        lastForeignApp = app
    }

    // MARK: - Apps excluidas

    private func rebuildExclusions() {
        exclusions = ClipboardFilter.exclusions(userList: excludedApps,
                                                includePasswordManagers: ignoreKnownPasswordManagers)
    }

    /// Añade a la lista la app de un paquete elegido en el Finder.
    /// Devuelve `false` si lo elegido no es una app o si ya estaba.
    @discardableResult
    func excludeApp(at url: URL) -> Bool {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return false }
        return excludeApp(bundleID: bundleID)
    }

    @discardableResult
    func excludeApp(bundleID: String) -> Bool {
        let id = ClipboardFilter.normalize(bundleID)
        guard !id.isEmpty,
              !excludedApps.contains(where: { ClipboardFilter.normalize($0) == id }) else { return false }
        excludedApps.append(id)
        return true
    }

    func stopExcluding(_ bundleID: String) {
        let id = ClipboardFilter.normalize(bundleID)
        excludedApps.removeAll { ClipboardFilter.normalize($0) == id }
    }

    /// Las apps de la lista del usuario, con nombre e icono para Ajustes.
    var excludedAppEntries: [ExcludedApp] { excludedApps.map { ExcludedApp(bundleID: $0) } }

    /// Los gestores de contraseñas conocidos que están instalados en este Mac.
    ///
    /// Ajustes enseña estos y no la lista entera: así se ve exactamente a quién cubre
    /// el interruptor aquí, en vez de prometer apps que uno no tiene. Se guarda la
    /// respuesta porque preguntar a LaunchServices no es gratis y la vista se redibuja
    /// muchas veces; quien instale un gestor lo verá en la lista al reabrir Ajustes,
    /// aunque el filtro ya lo esté ignorando desde el primer momento.
    var installedPasswordManagers: [ExcludedApp] {
        if let installedManagers { return installedManagers }
        let found = ClipboardFilter.passwordManagers
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            .map { ExcludedApp(bundleID: $0) }
        installedManagers = found
        return found
    }

    // MARK: - Interno

    /// Mira si hay algo nuevo en el portapapeles y lo guarda si toca.
    ///
    /// `attributingTo` es la app a la que atribuir lo copiado; sin ella se usa la que
    /// esté delante ahora mismo (ver el observador de activación en `start()`).
    private func poll(attributingTo app: String? = nil) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        lastChangeAt = Date()   // se acelera el sondeo mientras dure la racha

        let front = app ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardFilter.shouldRecord(types: (pasteboard.types ?? []).map(\.rawValue),
                                           frontmostBundleID: front,
                                           excluded: exclusions,
                                           paused: paused) else { return }

        // Archivos → texto → imagen (copiar un archivo también deja su nombre como texto).
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            if case .files(let existing)? = items.first?.content, existing == urls { return }
            items.removeAll {
                if case .files(let u) = $0.content { return u == urls }
                return false
            }
            insert(ClipItem(content: .files(urls)))
            return
        }

        if var text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Un texto larguísimo se recorta para no hinchar la memoria (y el disco,
            // si guardas el historial). Antes se recortaba en silencio y al pegarlo
            // te faltaba media página sin que nadie te avisara: ahora la fila lo dice.
            var trimmed = false
            if text.count > Self.maxTextLength {
                text = String(text.prefix(Self.maxTextLength))
                trimmed = true
            }
            // Si lo copiado es un enlace con rastreo, se sustituye por el limpio: en
            // el historial y en el portapapeles, para que al pegar salga ya limpio.
            if cleanURLs, let cleaned = URLCleaner.clean(text) {
                text = cleaned
                pasteboard.clearContents()
                pasteboard.setString(cleaned, forType: .string)
                lastChangeCount = pasteboard.changeCount
                Toast.show(L("Enlace limpio de rastreo", "Tracking removed from the link"),
                           symbol: "link")
            }
            if case .text(let existing)? = items.first?.content, existing == text { return }
            items.removeAll {
                if case .text(let t) = $0.content { return t == text }
                return false
            }
            insert(ClipItem(content: .text(text), truncated: trimmed))
            return
        }

        if let image = NSImage(pasteboard: pasteboard), image.size.width > 0 {
            // Imágenes enormes (capturas 5K…) sí; más de ~50 MB no.
            if let tiff = image.tiffRepresentation, tiff.count > 50_000_000 { return }
            insert(ClipItem(content: .image(image)))
        }
    }

    private func insert(_ item: ClipItem) {
        let firstUnpinned = items.firstIndex { !$0.pinned } ?? items.count
        items.insert(item, at: firstUnpinned)
        trim()
    }

    /// Descarta los más antiguos NO anclados por encima del límite.
    private func trim() {
        var unpinned = items.filter { !$0.pinned }.count
        guard unpinned > maxItems else { return }
        for index in stride(from: items.count - 1, through: 0, by: -1) where !items[index].pinned {
            items.remove(at: index)
            unpinned -= 1
            if unpinned <= maxItems { break }
        }
    }

    private func paste(_ item: ClipItem) {
        panel.hide()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let image):
            pasteboard.writeObjects([image])
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        lastChangeCount = pasteboard.changeCount

        // El elemento usado sube al principio (de su grupo: anclados o normales).
        items.removeAll { $0.id == item.id }
        let refreshed = ClipItem(id: item.id, content: item.content, date: Date(), pinned: item.pinned)
        if refreshed.pinned {
            items.insert(refreshed, at: 0)
        } else {
            items.insert(refreshed, at: items.firstIndex { !$0.pinned } ?? items.count)
        }

        previousApp?.activate()
        previousApp = nil

        // Sin Accesibilidad no podemos simular ⌘V: queda copiado y el usuario pega a mano.
        guard Permissions.hasAccessibility else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Self.sendCmdV()
        }
    }

    private static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Persistencia (opcional)

    private struct StoredItem: Codable {
        let id: UUID
        let date: Date
        let kind: String
        let text: String?
        let files: [String]?
        let image: String?
        var pinned: Bool? = false
        var truncated: Bool? = false
    }

    private static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniMac/Clipboard", isDirectory: true)
    }

    private func scheduleSave() {
        guard persist || items.contains(where: \.pinned) else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func saveNow() {
        let directory = Self.storeDirectory
        let imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        var keep = Set<String>()
        func encode(_ subset: [ClipItem]) -> [StoredItem] {
            var stored: [StoredItem] = []
            for item in subset {
                switch item.content {
                case .text(let text):
                    stored.append(StoredItem(id: item.id, date: item.date, kind: "text", text: text, files: nil, image: nil, pinned: item.pinned, truncated: item.truncated))
                case .files(let urls):
                    stored.append(StoredItem(id: item.id, date: item.date, kind: "files", text: nil, files: urls.map(\.path), image: nil, pinned: item.pinned))
                case .image(let image):
                    let name = "\(item.id.uuidString).png"
                    keep.insert(name)
                    let file = imagesDirectory.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: file.path),
                       let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: file)
                    }
                    stored.append(StoredItem(id: item.id, date: item.date, kind: "image", text: nil, files: nil, image: name, pinned: item.pinned))
                }
            }
            return stored
        }
        // Anclados: siempre. Historial normal: solo si «Guardar en disco» está activo.
        if let data = try? JSONEncoder().encode(encode(items.filter(\.pinned))) {
            try? data.write(to: directory.appendingPathComponent("pins.json"), options: .atomic)
        }
        let historyFile = directory.appendingPathComponent("history.json")
        if persist, let data = try? JSONEncoder().encode(encode(items.filter { !$0.pinned })) {
            try? data.write(to: historyFile, options: .atomic)
        } else if !persist {
            try? FileManager.default.removeItem(at: historyFile)
        }
        // Imágenes que ya no están en el historial.
        if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) {
            for file in files where !keep.contains(file) {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
            }
        }
    }

    private func load() {
        let directory = Self.storeDirectory
        func read(_ name: String, pinned: Bool) -> [ClipItem] {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let stored = try? JSONDecoder().decode([StoredItem].self, from: data) else { return [] }
            return stored.compactMap { entry in
                switch entry.kind {
                case "text":
                    return entry.text.map { ClipItem(id: entry.id, content: .text($0), date: entry.date,
                                                     pinned: pinned, truncated: entry.truncated ?? false) }
                case "files":
                    return entry.files.map { ClipItem(id: entry.id, content: .files($0.map { URL(fileURLWithPath: $0) }), date: entry.date, pinned: pinned) }
                case "image":
                    guard let name = entry.image,
                          let image = NSImage(contentsOf: directory.appendingPathComponent("images/\(name)")) else { return nil }
                    return ClipItem(id: entry.id, content: .image(image), date: entry.date, pinned: pinned)
                default:
                    return nil
                }
            }
        }
        var loaded = read("pins.json", pinned: true)
        if persist { loaded += read("history.json", pinned: false) }
        guard !loaded.isEmpty else { return }
        items = loaded
        sortItems()
    }

    /// Al desactivar «Guardar en disco»: fuera el historial normal (los anclados se quedan).
    private func deleteStore() {
        saveWork?.cancel()
        saveWork = nil
        try? FileManager.default.removeItem(at: Self.storeDirectory.appendingPathComponent("history.json"))
        saveNow()
    }
}
