import AppKit
import Carbon.HIToolbox
import Combine

/// Una disposición: dónde estaba cada ventana cuando se guardó.
struct WindowLayout: Codable, Identifiable {
    struct Entry: Codable {
        let bundleID: String
        let appName: String
        let title: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    var id = UUID()
    var name: String
    var screenCount: Int
    var savedAt: Date
    var windows: [Entry]
    /// Atajo ⌃⌥ + número (1–9); nil = sin atajo.
    var hotKey: Int?

    var appCount: Int { Set(windows.map(\.bundleID)).count }
    var shortcutLabel: String? { hotKey.map { "⌃⌥ \($0)" } }
}

/// Disposiciones de ventanas: guarda dónde está cada ventana y las vuelve a colocar
/// con un clic o con ⌃⌥1…⌃⌥9. Si lo activas, al conectar o quitar una pantalla se
/// aplica sola la última disposición guardada con ese número de pantallas.
final class WindowLayoutStore: ObservableObject {
    static let shared = WindowLayoutStore()

    @Published private(set) var layouts: [WindowLayout] = []
    @Published var autoApply: Bool {
        didSet { UserDefaults.standard.set(autoApply, forKey: "layouts.autoApply") }
    }

    private static let hotKeyBase: UInt32 = 500
    private static let undoHotKey: UInt32 = 510
    /// Códigos de tecla de 1…9 (índice 0 = tecla 1).
    private static let digitKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
        UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]
    /// Dónde estaban las ventanas antes de la última disposición aplicada (para deshacer).
    private var previousFrames: [(window: AXUIElement, frame: CGRect)] = []
    @Published private(set) var canUndo = false
    /// Toque vs. mantener pulsado ⌃⌥n.
    private var holdWork: DispatchWorkItem?
    private var holdConsumed = false
    private static let holdSeconds = 0.8
    private var screenObserver: Any?
    private var screenWork: DispatchWorkItem?
    private var lastScreenCount = NSScreen.screens.count
    private var running = false

    private static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("OmniMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layouts.json")
    }

    private init() {
        autoApply = UserDefaults.standard.bool(forKey: "layouts.autoApply")
        load()
    }

    func start() {
        guard !running else { return }
        running = true
        registerHotKeys()
        lastScreenCount = NSScreen.screens.count
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    func stop() {
        running = false
        unregisterHotKeys()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    // MARK: - Guardar, aplicar, borrar

    /// Guarda la disposición actual; si ya existe una con ese nombre, la sustituye.
    /// `hotKey`: número a asignar (se lo quita a quien lo tuviera); nil = el primero libre.
    @discardableResult
    func saveCurrent(named rawName: String, hotKey forcedKey: Int? = nil) -> WindowLayout? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let entries = capture()
        guard !entries.isEmpty else {
            Toast.show("No hay ventanas que guardar", symbol: "macwindow")
            return nil
        }
        var layout = WindowLayout(name: name, screenCount: NSScreen.screens.count, savedAt: Date(), windows: entries)
        if let forcedKey {
            for i in layouts.indices where layouts[i].hotKey == forcedKey { layouts[i].hotKey = nil }
        }
        if let index = layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            layout.hotKey = forcedKey ?? layouts[index].hotKey
            layouts[index] = layout
        } else {
            layout.hotKey = forcedKey ?? firstFreeHotKey()
            layouts.append(layout)
        }
        persist()
        let shortcut = layout.shortcutLabel.map { " · \($0)" } ?? ""
        Toast.show("Disposición «\(name)» guardada · \(entries.count) ventanas\(shortcut)", symbol: "square.grid.2x2.fill")
        return layout
    }

    /// Vuelve a capturar las ventanas para una disposición existente.
    func refresh(_ layout: WindowLayout) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        let entries = capture()
        guard !entries.isEmpty else { return }
        layouts[index].windows = entries
        layouts[index].screenCount = NSScreen.screens.count
        layouts[index].savedAt = Date()
        persist()
        Toast.show("«\(layout.name)» actualizada · \(entries.count) ventanas", symbol: "square.grid.2x2.fill")
    }

    func delete(_ layout: WindowLayout) {
        layouts.removeAll { $0.id == layout.id }
        persist()
        Toast.show("Disposición «\(layout.name)» eliminada", symbol: "trash")
    }

    /// Asigna (o quita) el atajo ⌃⌥n. Si otra disposición lo tenía, lo pierde.
    func setHotKey(_ key: Int?, for layout: WindowLayout) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        if let key {
            for i in layouts.indices where layouts[i].hotKey == key { layouts[i].hotKey = nil }
        }
        layouts[index].hotKey = key
        persist()
    }

    /// Devuelve las ventanas a donde estaban antes de la última disposición aplicada.
    func undoLast() {
        guard !previousFrames.isEmpty else {
            Toast.show("No hay ninguna disposición que deshacer", symbol: "arrow.uturn.backward")
            return
        }
        for (window, frame) in previousFrames {
            AX.setFrame(window, cocoaRect: frame)
        }
        let count = previousFrames.count
        previousFrames = []
        canUndo = false
        Toast.show("Deshecho · \(count) ventanas a su sitio", symbol: "arrow.uturn.backward")
    }

    private func firstFreeHotKey() -> Int? {
        let used = Set(layouts.compactMap(\.hotKey))
        return (1...9).first { !used.contains($0) }
    }

    // MARK: - ⌃⌥n como "preset": toque guarda o aplica; mantener libera el número

    private func slotPressed(_ key: Int) {
        holdWork?.cancel()
        holdConsumed = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.holdConsumed = true
            self.freeSlot(key)
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds, execute: work)
    }

    private func slotReleased(_ key: Int) {
        holdWork?.cancel()
        holdWork = nil
        if holdConsumed {
            holdConsumed = false
            return
        }
        if let layout = layouts.first(where: { $0.hotKey == key }) {
            apply(layout)
        } else {
            let name = "Disposición \(key)"
            if saveCurrent(named: name, hotKey: key) != nil {
                Toast.show("Guardada en ⌃⌥\(key) · toca para aplicarla, mantén pulsado para liberarla",
                           symbol: "square.grid.2x2.fill", duration: 3)
            }
        }
    }

    private func freeSlot(_ key: Int) {
        guard let index = layouts.firstIndex(where: { $0.hotKey == key }) else {
            Toast.show("⌃⌥\(key) ya estaba libre", symbol: "keyboard")
            return
        }
        let name = layouts[index].name
        layouts[index].hotKey = nil
        persist()
        Toast.show("⌃⌥\(key) libre · «\(name)» sigue en Ajustes sin atajo", symbol: "keyboard", duration: 3)
    }

    /// Coloca las ventanas. Las apps que no estén abiertas se ignoran (se avisa).
    func apply(_ layout: WindowLayout) {
        guard Permissions.hasAccessibility else {
            Permissions.requestAccessibility()
            Toast.show("Necesita el permiso de Accesibilidad", symbol: "exclamationmark.shield.fill")
            return
        }
        var placed = 0
        var missingApps = Set<String>()
        previousFrames = []
        let byApp = Dictionary(grouping: layout.windows, by: \.bundleID)
        for (bundleID, entries) in byApp {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                missingApps.insert(entries.first?.appName ?? bundleID)
                continue
            }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.5)
            var windows = AX.elements(axApp, kAXWindowsAttribute as String).filter {
                AX.string($0, kAXSubroleAttribute as String) == kAXStandardWindowSubrole as String
            }
            // Primero por título exacto; lo que quede, por orden.
            var pending: [WindowLayout.Entry] = []
            for entry in entries {
                if let index = windows.firstIndex(where: { AX.string($0, kAXTitleAttribute as String) == entry.title }) {
                    place(windows.remove(at: index), entry)
                    placed += 1
                } else {
                    pending.append(entry)
                }
            }
            for entry in pending {
                guard !windows.isEmpty else { break }
                place(windows.removeFirst(), entry)
                placed += 1
            }
        }
        canUndo = !previousFrames.isEmpty
        var message = "«\(layout.name)»: \(placed) ventanas colocadas"
        if !missingApps.isEmpty {
            message += " · sin abrir: \(missingApps.sorted().joined(separator: ", "))"
        }
        if placed > 0 { message += " · ⌃⌥0 deshace" }
        Toast.show(message, symbol: "square.grid.2x2.fill", duration: missingApps.isEmpty ? 2.2 : 3.5)
    }

    // MARK: - Interno

    private func place(_ window: AXUIElement, _ entry: WindowLayout.Entry) {
        // Guardamos dónde estaba, para poder deshacer.
        if let position = AX.point(window, kAXPositionAttribute as String),
           let size = AX.size(window, kAXSizeAttribute as String) {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            previousFrames.append((window, CGRect(x: position.x, y: primaryHeight - position.y - size.height,
                                                  width: size.width, height: size.height)))
        }
        if AX.bool(window, kAXMinimizedAttribute as String) {
            AX.set(window, kAXMinimizedAttribute as String, to: kCFBooleanFalse)
        }
        AX.setFrame(window, cocoaRect: entry.frame)
    }

    private func capture() -> [WindowLayout.Entry] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var entries: [WindowLayout.Entry] = []
        for window in WindowEnumerator.windows(includeMinimized: false) {
            guard let app = NSRunningApplication(processIdentifier: window.pid),
                  let bundleID = app.bundleIdentifier,
                  let position = AX.point(window.axElement, kAXPositionAttribute as String),
                  let size = AX.size(window.axElement, kAXSizeAttribute as String),
                  size.width > 50, size.height > 50 else { continue }
            let title = AX.string(window.axElement, kAXTitleAttribute as String) ?? ""
            entries.append(WindowLayout.Entry(bundleID: bundleID,
                                              appName: window.appName,
                                              title: title,
                                              x: position.x,
                                              y: primaryHeight - position.y - size.height,
                                              width: size.width,
                                              height: size.height))
        }
        return entries
    }

    private func screensChanged() {
        screenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let count = NSScreen.screens.count
            guard count != self.lastScreenCount else { return }
            self.lastScreenCount = count
            guard self.autoApply,
                  let layout = self.layouts.filter({ $0.screenCount == count }).max(by: { $0.savedAt < $1.savedAt }) else { return }
            self.apply(layout)
        }
        screenWork = work
        // Las pantallas tardan un poco en asentarse tras conectar o quitar una.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        let modifiers = UInt32(controlKey | optionKey)
        // Los nueve números siempre: un número libre guarda; uno ocupado aplica.
        for key in 1...9 {
            HotKeyCenter.shared.register(id: Self.hotKeyBase + UInt32(key),
                                         keyCode: Self.digitKeyCodes[key - 1],
                                         modifiers: modifiers,
                                         handler: { [weak self] in self?.slotPressed(key) },
                                         onRelease: { [weak self] in self?.slotReleased(key) })
        }
        // ⌃⌥0: deshacer la última disposición aplicada.
        HotKeyCenter.shared.register(id: Self.undoHotKey, keyCode: UInt32(kVK_ANSI_0), modifiers: modifiers) { [weak self] in
            self?.undoLast()
        }
    }

    private func unregisterHotKeys() {
        for key in 1...9 { HotKeyCenter.shared.unregister(id: Self.hotKeyBase + UInt32(key)) }
        HotKeyCenter.shared.unregister(id: Self.undoHotKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(layouts) {
            try? data.write(to: Self.file, options: .atomic)
        }
        if running { registerHotKeys() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let stored = try? JSONDecoder().decode([WindowLayout].self, from: data) else { return }
        layouts = stored
        // Disposiciones de antes (sin atajo propio): conservan el número que tenían por posición.
        var changed = false
        var used = Set(layouts.compactMap(\.hotKey))
        for index in layouts.indices where layouts[index].hotKey == nil {
            let candidate = index + 1
            if candidate <= 9, !used.contains(candidate) {
                layouts[index].hotKey = candidate
                used.insert(candidate)
                changed = true
            }
        }
        if changed, let data = try? JSONEncoder().encode(layouts) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
