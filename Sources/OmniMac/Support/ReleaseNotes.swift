import AppKit
import Foundation

/// Las novedades de una versión, tal y como se enseñan tras actualizar.
///
/// Salen del `CHANGELOG.md` que ya mantenemos, empaquetado dentro de la app: así las
/// novedades se escriben **una sola vez** y no hay forma de que la ventana diga una
/// cosa y el archivo otra.
struct ReleaseNotes: Equatable {
    let version: String
    /// Tal y como está escrita en el archivo (`2026-09-06`), o nada si no la lleva.
    let date: String?
    let items: [String]
    /// Cuáles de `items` están bajo el subtítulo **Arreglado**.
    ///
    /// Hace falta para que el tour no te pasee por los arreglos: al actualizar
    /// quieres ver lo nuevo, y lo que se arregló lo lees si te apetece.
    let fixedFrom: Int?

    /// Lo nuevo, sin los arreglos.
    var newItems: [String] { Array(items.prefix(fixedFrom ?? items.count)) }

    /// Todas las versiones del archivo, de la más nueva a la más vieja.
    ///
    /// El formato es el del propio archivo: `## 0.4.2 — 2026-09-06` abre una versión
    /// y las líneas que empiezan por `- ` son sus novedades. Los subtítulos en negrita
    /// (`**Nuevo**`) no se pintan, pero sí se usan para saber dónde empiezan los
    /// arreglos.
    static func all(from markdown: String) -> [ReleaseNotes] {
        var result: [ReleaseNotes] = []
        var version: String?
        var date: String?
        var items: [String] = []
        var fixedFrom: Int?

        func flush() {
            if let version, !items.isEmpty {
                result.append(ReleaseNotes(version: version, date: date, items: items, fixedFrom: fixedFrom))
            }
            version = nil; date = nil; items = []; fixedFrom = nil
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                flush()
                // «0.4.2 — 2026-09-06», con guion largo o corto, y la fecha es opcional.
                let heading = String(trimmed.dropFirst(3))
                let parts = heading.components(separatedBy: CharacterSet(charactersIn: "—–-"))
                version = parts.first?.trimmingCharacters(in: .whitespaces)
                if parts.count > 1 {
                    let rest = parts.dropFirst().joined(separator: "-").trimmingCharacters(in: .whitespaces)
                    date = rest.isEmpty ? nil : rest
                }
            } else if trimmed.hasPrefix("**"), version != nil {
                let heading = trimmed.lowercased()
                if heading.contains("arreglado") || heading.contains("fixed") || heading.contains("corregido") {
                    fixedFrom = items.count
                }
            } else if trimmed.hasPrefix("- "), version != nil {
                items.append(clean(String(trimmed.dropFirst(2))))
            }
        }
        flush()
        return result
    }

    /// Las novedades de una versión concreta.
    static func notes(for version: String, in markdown: String) -> ReleaseNotes? {
        all(from: markdown).first { $0.version == version }
    }

    /// Quita el formato de Markdown que no sabemos pintar (negritas, código y
    /// enlaces), dejando el texto legible.
    private static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "**", with: "")
                         .replacingOccurrences(of: "`", with: "")
        // [texto](enlace) → texto
        while let open = result.firstIndex(of: "["),
              let close = result[open...].firstIndex(of: "]"),
              result.index(after: close) < result.endIndex,
              result[result.index(after: close)] == "(",
              let end = result[close...].firstIndex(of: ")") {
            let label = String(result[result.index(after: open)..<close])
            result.replaceSubrange(open...end, with: label)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Una novedad, lista para enseñar

    /// Una novedad tal y como se pinta en el recorrido: un icono, un titular corto y
    /// el texto entero.
    struct Highlight: Equatable, Identifiable {
        let title: String
        let detail: String
        let symbol: String

        var id: String { title + detail }
    }

    /// Convierte las líneas del CHANGELOG en pantallas del recorrido.
    ///
    /// Nuestras novedades se escriben casi siempre como «Zona: qué cambia», así que el
    /// titular sale de lo que hay antes de los dos puntos y el resto es el detalle.
    /// Cuando no hay dos puntos, el titular es el módulo que se adivine por el texto.
    /// Como mucho ocho pantallas.
    ///
    /// Una versión con veintitrés novedades no se cuenta en veintitrés pantallas:
    /// nadie pulsa «Siguiente» veintitrés veces. Se enseñan las primeras, que son las
    /// que se escriben primero por algo, y el resto está en el CHANGELOG.
    static let maxHighlights = 8

    var highlights: [Highlight] {
        // Una pantalla por área. Si no, una versión con cuatro mejoras de sonido
        // seguidas se lleva medio recorrido y el resto de la app no sale.
        var seen = Set<String>()
        let picked = newItems.filter { seen.insert(Self.area(for: $0)).inserted }
        return picked.prefix(Self.maxHighlights).map { item in
            let symbol = Self.symbol(for: item)
            guard let colon = item.firstIndex(of: ":"), colon > item.startIndex else {
                return Highlight(title: Self.area(for: item), detail: item, symbol: symbol)
            }
            let title = String(item[item.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let detail = String(item[item.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // Un titular larguísimo no es un titular.
            guard title.count <= 42, !detail.isEmpty else {
                return Highlight(title: Self.area(for: item), detail: item, symbol: symbol)
            }
            return Highlight(title: title, detail: detail.prefix(1).capitalized + detail.dropFirst(), symbol: symbol)
        }
    }

    /// Icono por el asunto del que habla la novedad.
    static func symbol(for text: String) -> String {
        let lower = text.lowercased()
        let table: [(String, String)] = [
            ("notch", "sparkles.rectangle.stack"),
            ("ecualizador", "slider.vertical.3"),
            ("equalizer", "slider.vertical.3"),
            ("equaliser", "slider.vertical.3"),
            ("sonido", "speaker.wave.3.fill"),
            ("sound", "speaker.wave.3.fill"),
            ("volumen", "speaker.wave.2.fill"),
            ("barra de menús", "menubar.rectangle"),
            ("menu bar", "menubar.rectangle"),
            ("portapapeles", "doc.on.clipboard"),
            ("clipboard", "doc.on.clipboard"),
            ("ventana", "rectangle.split.2x1"),
            ("window", "rectangle.split.2x1"),
            ("despierto", "cup.and.saucer.fill"),
            ("awake", "cup.and.saucer.fill"),
            ("temporizador", "timer"),
            ("timer", "timer"),
            ("limpiador", "trash"),
            ("cleaner", "trash"),
            ("caché", "internaldrive"),
            ("cache", "internaldrive"),
            ("almacenamiento", "internaldrive"),
            ("rendimiento", "gauge.with.dots.needle.33percent"),
            ("performance", "gauge.with.dots.needle.33percent"),
            ("idioma", "globe"),
            ("language", "globe"),
            ("ajustes", "gearshape.fill"),
            ("settings", "gearshape.fill"),
            ("airpods", "airpods.gen3"),
            ("calendario", "calendar"),
            ("calendar", "calendar"),
            ("temperatura", "thermometer.medium"),
            ("temperature", "thermometer.medium"),
            ("buscador de comandos", "command"),
            ("command bar", "command"),
            ("brillo", "sun.min.fill"),
            ("brightness", "sun.min.fill"),
            ("aviso", "bell.badge"),
            ("alerta", "bell.badge"),
            ("alert", "bell.badge"),
            ("enlace", "link"),
            ("link", "link"),
            ("descarga", "arrow.down.circle"),
            ("download", "arrow.down.circle"),
            ("amplificación", "speaker.wave.3.fill"),
            ("boost", "speaker.wave.3.fill"),
            ("mezclador", "slider.horizontal.3"),
            ("mixer", "slider.horizontal.3"),
        ]
        for (needle, symbol) in table where lower.contains(needle) {
            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil { return symbol }
        }
        return "sparkles"
    }

    /// Nombre corto del asunto, para cuando la línea no trae «Zona: …».
    private static func area(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("notch") { return "Notch" }
        if lower.contains("sonido") || lower.contains("sound") { return L("Sonido", "Sound") }
        if lower.contains("ventana") || lower.contains("window") { return L("Ventanas", "Windows") }
        if lower.contains("barra de menús") || lower.contains("menu bar") { return L("Barra de menús", "Menu bar") }
        if lower.contains("rendimiento") || lower.contains("performance") { return L("Rendimiento", "Performance") }
        if lower.contains("portapapeles") || lower.contains("clipboard") { return L("Portapapeles", "Clipboard") }
        if lower.contains("limpiador") || lower.contains("cleaner") { return L("Limpiador", "Cleaner") }
        if lower.contains("ecualizador") || lower.contains("equaliser") || lower.contains("equalizer")
            || lower.contains("amplificación") || lower.contains("boost")
            || lower.contains("salida") || lower.contains("output") || lower.contains("mezclador")
            || lower.contains("mixer") || lower.contains("auriculares") { return L("Sonido", "Sound") }
        if lower.contains("pegar") || lower.contains("paste") || lower.contains("enlace")
            || lower.contains("link") { return L("Portapapeles", "Clipboard") }
        if lower.contains("brillo") || lower.contains("brightness") { return L("Utilidades", "Tools") }
        if lower.contains("aviso") || lower.contains("alert") { return L("Avisos", "Alerts") }
        if lower.contains("temperatura") || lower.contains("temperature") { return L("Temperatura", "Temperature") }
        if lower.contains(".dmg") || lower.contains("descarga") || lower.contains("download") { return L("Descargas", "Downloads") }
        return L("Novedad", "New")
    }

    // MARK: - Cuándo enseñarlas

    static let lastVersionKey = "app.lastVersionSeen"

    /// ¿Hay que enseñar las novedades al arrancar?
    ///
    /// Solo cuando la versión ha cambiado respecto a la última que se vio. En una
    /// instalación nueva no se enseña nada: ahí lo que sale es la bienvenida, y
    /// recibir dos ventanas seguidas es de mal gusto.
    static func shouldShow(current: String, lastSeen: String?) -> Bool {
        guard let lastSeen, !lastSeen.isEmpty else { return false }
        return lastSeen != current
    }
}
