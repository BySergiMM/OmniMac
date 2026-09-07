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

/// Dónde busca restos el limpiador.
struct LeftoverPlace {
    let title: String
    let path: String
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
