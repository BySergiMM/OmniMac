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

    init(id: UUID = UUID(), content: Content, date: Date = Date(), pinned: Bool = false) {
        self.id = id
        self.content = content
        self.date = date
        self.pinned = pinned
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

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let panel = ClipboardPanelController()
    private var previousApp: NSRunningApplication?
    private var saveWork: DispatchWorkItem?

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
        super.init(id: "clipboard",
                   name: L("Historial del portapapeles", "Clipboard history"),
                   symbol: "doc.on.clipboard",
                   blurb: L("Guarda lo que copias (texto, imágenes y archivos) y pégalo cuando quieras con ⇧⌘V.", "Saves what you copy (text, images and files) and pastes it whenever you want with ⇧⌘V."),
                   defaultEnabled: true)

        panel.onSelect = { [weak self] item in self?.paste(item) }
        panel.onDelete = { [weak self] item in self?.remove(item) }
        panel.onPin = { [weak self] item in self?.togglePin(item) }
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
        // 1 Hz con tolerancia: el sistema agrupa los despertares y apenas consume.
        // Al abrir el panel se sondea al momento, así que nada se pierde.
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        t.tolerance = 0.3
        timer = t
        HotKeyCenter.shared.bind(Self.historyShortcut) { [weak self] in self?.togglePanel() }
        if plainPasteEnabled { registerPlainPaste() }
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
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.show(items: items)
    }

    // MARK: - Interno

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !paused else { return }

        let types = pasteboard.types ?? []
        // Respetamos las marcas estándar: nada de contraseñas ni copias transitorias.
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return }
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")) { return }

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
            if text.count > 20_000 {
                text = String(text.prefix(20_000))
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
            insert(ClipItem(content: .text(text)))
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
                    stored.append(StoredItem(id: item.id, date: item.date, kind: "text", text: text, files: nil, image: nil, pinned: item.pinned))
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
                    return entry.text.map { ClipItem(id: entry.id, content: .text($0), date: entry.date, pinned: pinned) }
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
