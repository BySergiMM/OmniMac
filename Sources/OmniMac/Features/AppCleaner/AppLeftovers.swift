import Foundation

/// Una app instalada, tal y como la enseña el limpiador.
struct InstalledApp: Identifiable, Equatable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    var size: Int64 = 0

    var id: URL { url }
}

/// Un archivo o carpeta que dejó una app por el sistema.
struct Leftover: Identifiable, Equatable {
    /// Dónde estaba (para agrupar en la lista: «Preferencias», «Cachés»…).
    let place: String
    let url: URL
    let size: Int64
    /// Fuera de la carpeta del usuario hace falta contraseña de administrador, así
    /// que estos se enseñan pero no se marcan solos.
    let needsAdmin: Bool

    var id: URL { url }
}

/// Decide si un archivo suelto pertenece a una app.
///
/// Está separado del escaneo a propósito: son las reglas que deciden qué se va a la
/// papelera, así que tienen que poder probarse sin tocar el disco de nadie.
enum LeftoverMatcher {
    /// Extensiones que macOS le pone a los restos y que hay que quitar antes de comparar.
    private static let strippable = [".plist", ".savedState", ".binarycookies", ".lockfile"]

    /// Identificadores que no se tocan jamás, aunque coincidan.
    static func isProtected(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id.hasPrefix("com.apple.") || id.isEmpty
    }

    /// - Parameters:
    ///   - fileName: nombre del archivo o carpeta encontrado.
    ///   - bundleID: identificador de la app (`com.spotify.client`).
    ///   - appName: nombre visible de la app («Spotify»).
    ///   - allowNameMatch: si vale comparar por nombre visible. Solo en las carpetas
    ///     donde las apps guardan cosas con su nombre (Application Support, Logs);
    ///     en el resto sería peligroso, porque una carpeta llamada «Notas» puede ser
    ///     de cualquiera.
    static func belongs(fileName: String, bundleID: String, appName: String, allowNameMatch: Bool) -> Bool {
        guard !isProtected(bundleID: bundleID) else { return false }

        var name = fileName
        for ext in strippable where name.hasSuffix(ext) {
            name.removeLast(ext.count)
            break
        }
        if name == bundleID { return true }

        // Ayudantes y subpaquetes: com.empresa.app.helper, com.empresa.app-updater…
        for separator in [".", "-", "_"] where name.hasPrefix(bundleID + separator) {
            return true
        }

        // Contenedores de grupo: van con el identificador de equipo delante
        // (ABCDE12345.com.empresa.app) o con «group.» delante.
        if name.hasSuffix("." + bundleID) {
            let prefix = String(name.dropLast(bundleID.count + 1))
            if prefix.lowercased() == "group" { return true }
            if prefix.count == 10, prefix.allSatisfy({ $0.isLetter || $0.isNumber }) { return true }
        }

        if allowNameMatch, !appName.isEmpty, name.compare(appName, options: .caseInsensitive) == .orderedSame {
            return true
        }
        return false
    }

    /// Carpetas genéricas que nunca identifican a un fabricante.
    private static let genericVendors: Set<String> = ["com", "org", "net", "io", "co", "app", "apps", "dev", "me", "sh", "www"]

    /// Muchas apps no guardan sus datos con su identificador, sino dentro de una
    /// carpeta con el nombre del fabricante: `Application Support/Google/Chrome`.
    /// El fabricante sale del propio identificador (`com.google.Chrome` → `google`).
    ///
    /// La carpeta del fabricante **no** se toca nunca, porque puede tener dentro
    /// datos de otras apps suyas; solo se mira lo que hay dentro.
    static func vendor(bundleID: String) -> String? {
        guard !isProtected(bundleID: bundleID) else { return nil }
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let vendor = String(parts[1])
        guard vendor.count >= 3, !genericVendors.contains(vendor.lowercased()) else { return nil }
        return vendor
    }

    /// ¿Es `fileName` la carpeta de esta app dentro de la carpeta del fabricante?
    /// Aquí se compara por nombre exacto y nada más: es la única forma de no
    /// llevarse los datos de otra app del mismo fabricante.
    static func belongsInsideVendorFolder(fileName: String, bundleID: String, appName: String) -> Bool {
        guard !isProtected(bundleID: bundleID) else { return false }
        if fileName == bundleID { return true }
        if !appName.isEmpty, fileName.compare(appName, options: .caseInsensitive) == .orderedSame { return true }
        if let last = bundleID.split(separator: ".").last.map(String.init), !last.isEmpty,
           fileName.compare(last, options: .caseInsensitive) == .orderedSame { return true }
        return false
    }
}

/// Restos de una app que ya no está instalada.
struct OrphanLeftover: Identifiable, Equatable {
    /// El identificador que se dedujo del nombre del archivo (`com.spotify.client`).
    let bundleID: String
    /// Nombre legible: el último trozo del identificador («Client» → «Spotify»).
    let name: String
    let urls: [URL]
    /// Se rellena en una segunda pasada: medirlo todo antes de enseñar nada tardaba
    /// más de diez minutos.
    var size: Int64

    var id: String { bundleID }
}

/// Reglas para decidir si un archivo suelto **parece** de una app y de cuál.
enum OrphanRules {
    /// ¿El nombre de este archivo es un identificador de app?
    ///
    /// Se piden al menos tres trozos separados por puntos y nada de espacios: así
    /// entran `com.spotify.client` y se quedan fuera las carpetas con nombre normal
    /// («Google», «Adobe», «Datos de usuario»), que pueden ser de cualquiera.
    static func bundleID(from fileName: String) -> String? {
        var name = fileName
        for ext in [".plist", ".savedState", ".binarycookies", ".lockfile"] where name.hasSuffix(ext) {
            name.removeLast(ext.count)
            break
        }
        // Contenedores de grupo. Vienen envueltos de varias formas y a veces
        // encadenadas: «243LU875E5.groups.com.apple.podcasts» lleva el identificador
        // de equipo **y** «groups.» delante. Se pelan todas las capas, porque si
        // queda una, «com.apple» deja de reconocerse y Podcasts sale como si fuera
        // el resto de una app desinstalada.
        var peeled = true
        while peeled {
            peeled = false
            for wrapper in ["group.", "groups.", "systemgroup."] where name.hasPrefix(wrapper) {
                name.removeFirst(wrapper.count)
                peeled = true
                break
            }
            if !peeled, name.count > 11, let dot = name.firstIndex(of: ".") {
                let prefix = String(name[name.startIndex..<dot])
                if prefix.count == 10, prefix.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    name = String(name[name.index(after: dot)...])
                    peeled = true
                }
            }
        }
        let parts = name.split(separator: ".")
        guard parts.count >= 3, !name.contains(" "), !name.contains("/"),
              parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard !LeftoverMatcher.isProtected(bundleID: name) else { return nil }
        return name
    }

    /// Cosas de Apple cuyo identificador **no** empieza por `com.apple.`.
    ///
    /// Atajos todavía usa `is.workflow` (era Workflow antes de que Apple la comprara)
    /// y la app TV usa `tvappservices`. Sin esta lista salen como restos de apps
    /// desinstaladas, que es justo lo contrario de la verdad.
    static let systemPrefixes = ["com.apple", "is.workflow", "tvappservices", "com.me", "com.icloud",
                                 "systemgroup.com.apple", "developer.apple"]

    /// Trozos que viven **dentro** de otras apps: marcos, actualizadores, informes de
    /// fallos. No son apps que hayas borrado, así que ofrecerlos no tiene sentido.
    static let sharedComponents = ["org.sparkle-project", "com.plausiblelabs", "org.swift", "org.cups",
                                   "io.branch", "com.crashlytics", "com.electron", "org.chromium",
                                   "com.microsoft.autoupdate", "com.adobe.crashreporter", "com.squirrel"]

    static func isSystem(_ bundleID: String) -> Bool { matches(bundleID, systemPrefixes) }
    static func isSharedComponent(_ bundleID: String) -> Bool { matches(bundleID, sharedComponents) }

    private static func matches(_ bundleID: String, _ prefixes: [String]) -> Bool {
        let id = bundleID.lowercased()
        return prefixes.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    /// El fabricante: los dos primeros trozos. `com.spotify.client` → `com.spotify`.
    ///
    /// Sirve para no ofrecer restos de una app que sigues teniendo. Tienes WhatsApp
    /// instalado y en Contenedores de grupo hay `group.net.whatsapp.family`: nadie
    /// va a encontrar una app llamada `net.whatsapp.family`, pero el fabricante
    /// `net.whatsapp` sí tiene apps, así que se deja en paz.
    static func vendor(of bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".").lowercased()
    }

    /// Trozos finales que no dicen nada: si el identificador acaba así, el nombre
    /// bueno es el del medio (`com.spotify.client` → «Spotify», no «Client»).
    private static let genericTails: Set<String> = ["client", "app", "mac", "macos", "osx", "desktop",
                                                    "cli", "helper", "shared", "family", "container",
                                                    "default", "main", "ui"]

    /// Nombre presentable a partir del identificador: `org.p0deje.Maccy` → «Maccy»,
    /// `com.spotify.client` → «Spotify».
    static func displayName(for bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return bundleID }
        let last = parts[parts.count - 1]
        let candidate = genericTails.contains(last.lowercased()) || parts.count < 3 ? parts[parts.count - 2] : last
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }
}

/// Dónde busca restos el limpiador.
struct LeftoverPlace {
    let title: String
    let path: String
    /// Carpetas que **ninguna app puede tocar**, ni con Acceso total al disco.
    ///
    /// `~/Library/Containers` y `~/Library/Group Containers` los gestiona
    /// `containermanagerd`: se puede escribir dentro, pero mover la carpeta —o su
    /// propio `.metadata.plist`— falla con `NSCocoaErrorDomain 513` y un
    /// `OSStatus -5000` por debajo. Comprobado: falla igual desde una shell con
    /// permisos amplios. Solo el Finder tiene el trato especial que hace falta.
    var systemProtected: Bool { path.contains("Containers") }
    /// Dentro de la carpeta del usuario (`~`) o del sistema (hace falta contraseña).
    let inHome: Bool
    /// Si vale comparar por el nombre visible de la app además de por identificador.
    let allowNameMatch: Bool

    var url: URL {
        inHome ? URL(fileURLWithPath: NSHomeDirectory()).appending(path: path)
               : URL(fileURLWithPath: "/" + path)
    }

    /// Las carpetas donde las apps de macOS dejan sus cosas, en el orden en que se
    /// enseñan. Todo lo que hay fuera de esta lista no se mira siquiera.
    static let all: [LeftoverPlace] = [
        .init(title: L("Preferencias", "Preferences"), path: "Library/Preferences", inHome: true, allowNameMatch: false),
        .init(title: L("Soporte de la app", "Application support"), path: "Library/Application Support", inHome: true, allowNameMatch: true),
        .init(title: L("Cachés", "Caches"), path: "Library/Caches", inHome: true, allowNameMatch: true),
        .init(title: L("Contenedores", "Containers"), path: "Library/Containers", inHome: true, allowNameMatch: false),
        .init(title: L("Contenedores de grupo", "Group containers"), path: "Library/Group Containers", inHome: true, allowNameMatch: false),
        .init(title: L("Estado guardado", "Saved state"), path: "Library/Saved Application State", inHome: true, allowNameMatch: false),
        .init(title: L("Registros", "Logs"), path: "Library/Logs", inHome: true, allowNameMatch: true),
        .init(title: L("Datos web", "Web data"), path: "Library/HTTPStorages", inHome: true, allowNameMatch: false),
        .init(title: L("Datos web", "Web data"), path: "Library/WebKit", inHome: true, allowNameMatch: false),
        .init(title: L("Cookies", "Cookies"), path: "Library/Cookies", inHome: true, allowNameMatch: false),
        .init(title: L("Scripts", "Scripts"), path: "Library/Application Scripts", inHome: true, allowNameMatch: false),
        .init(title: L("Arranque automático", "Launch at login"), path: "Library/LaunchAgents", inHome: true, allowNameMatch: false),
        .init(title: L("Soporte del sistema", "System support"), path: "Library/Application Support", inHome: false, allowNameMatch: true),
        .init(title: L("Arranque del sistema", "System launch items"), path: "Library/LaunchAgents", inHome: false, allowNameMatch: false),
        .init(title: L("Servicios en segundo plano", "Background services"), path: "Library/LaunchDaemons", inHome: false, allowNameMatch: false),
        .init(title: L("Ayudantes con privilegios", "Privileged helpers"), path: "Library/PrivilegedHelperTools", inHome: false, allowNameMatch: false),
    ]
}
