import Foundation

/// Qué hay en una ruta, sin seguir enlaces simbólicos: `FileManager.fileExists` y compañía
/// sí los siguen, y un enlace llamado `Foo.app` que apunta a otra parte pasaría por la app.
enum ItemKind: Equatable {
    case folder
    case symbolicLink
    case file
    case missing

    static func of(_ url: URL) -> ItemKind {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else { return .missing }
        switch type {
        case .typeDirectory: return .folder
        case .typeSymbolicLink: return .symbolicLink
        default: return .file
        }
    }
}

/// El tramo de archivos de instalar una app desde un `.dmg`: copiarla a un sitio
/// provisional, comprobar que lo copiado es lo que se revisó, dejarle su marca de
/// «descargado de Internet» y solo entonces cambiarla por lo que hubiera.
///
/// El orden importa. Antes la app anterior iba a la papelera **antes** de copiar, así que
/// un fallo al copiar (disco lleno, permisos) dejaba al usuario sin ninguna de las dos.
/// Ahora todo lo que puede fallar ocurre antes de tocar lo que ya hay, y lo único que
/// queda después es un renombrado en la misma carpeta.
///
/// Lo que habla con el sistema entra por `Environment`, así que las pruebas usan
/// carpetas de verdad pero firmas, papelera y marcas de mentira.
enum AppInstall {

    struct Environment {
        /// Qué es la app de esa ruta: quién la firmó y qué lleva dentro. `nil` si no se pudo
        /// leer, y entonces no coincide con nada.
        var identity: (URL) -> AppIdentity?
        /// Manda algo a la papelera y dice dónde ha quedado.
        var trash: (URL) throws -> URL?
        var readQuarantine: (URL) -> String?
        /// `false` si no se pudo escribir.
        var writeQuarantine: (String, URL) -> Bool
        /// El último paso: poner la copia en su sitio (origen, destino). Entra por aquí para
        /// poder probar qué pasa cuando falla justo después de mandar la anterior a la papelera.
        var place: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    }

    enum Failure: Error, Equatable {
        /// Lo que se iba a copiar no es una carpeta de verdad (es un enlace, o un archivo).
        case notAnApp
        case copyFailed(String)
        /// La copia no es lo que se le enseñó al usuario: otro firmante, o el mismo pero con
        /// otro contenido (lo único que distingue a dos apps sin firma).
        case changedSinceReview
        /// El `.dmg` estaba en cuarentena y no se ha podido dejar la copia igual: se
        /// prefiere no instalar a instalar saltándose la revisión de Gatekeeper.
        case quarantineNotApplied
        case replaceFailed(String)
    }

    /// Instala `source` (la app dentro del disco montado) en `folder` y devuelve dónde ha
    /// quedado.
    ///
    /// - `expecting`: lo que se le enseñó al usuario al pedirle permiso.
    /// - `imageQuarantine`: la marca del `.dmg` (`nil` si no la tenía).
    static func install(source: URL, into folder: URL, expecting: AppIdentity,
                        imageQuarantine: String?, using environment: Environment) -> Result<URL, Failure> {
        let files = FileManager.default
        let name = source.lastPathComponent
        let target = folder.appending(path: name)

        // Un enlace llamado «Foo.app» se copiaría como enlace, y lo que se comprobara después
        // sería su destino, que puede cambiar cuando uno quiera.
        guard ItemKind.of(source) == .folder else { return .failure(.notAnApp) }

        // Provisional, en la misma carpeta que el destino: así el último paso es un
        // renombrado dentro del mismo volumen y no una segunda copia.
        let staging = folder.appending(path: "\(stagingPrefix)\(UUID().uuidString)")
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
        // Pase lo que pase, la carpeta provisional se va: la ha creado esta función y solo
        // contiene la copia. (Si el proceso muere a mitad, la barre `removeLeftovers`.)
        defer { try? files.removeItem(at: staging) }

        let staged = staging.appending(path: name)
        do {
            try files.copyItem(at: source, to: staged)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }

        // Se comprueba la copia, que es lo que se va a instalar, y no el disco: así lo que
        // se mira es exactamente lo que acaba en Aplicaciones. Con la huella del contenido,
        // porque el firmante solo no distingue una app sin firma de otra.
        guard environment.identity(staged) == expecting else { return .failure(.changedSinceReview) }

        if let value = QuarantineMark.valueForCopy(image: imageQuarantine, app: environment.readQuarantine(staged)) {
            guard environment.writeQuarantine(value, staged) else { return .failure(.quarantineNotApplied) }
        }

        // Hasta aquí no se ha tocado nada de lo que ya había.
        var trashed: URL?
        // `ItemKind` y no `fileExists`: este último sigue los enlaces, y un enlace roto con ese
        // nombre pasaría por «no hay nada» y luego estorbaría al colocar la copia.
        if ItemKind.of(target) != .missing {
            do {
                trashed = try environment.trash(target)
            } catch {
                return .failure(.replaceFailed(error.localizedDescription))
            }
        }
        do {
            try environment.place(staged, target)
        } catch {
            // Lo anterior vuelve a su sitio, si se puede.
            if let previous = trashed { try? files.moveItem(at: previous, to: target) }
            return .failure(.replaceFailed(error.localizedDescription))
        }
        return .success(target)
    }

    // MARK: - Lo que deja una instalación interrumpida

    static let stagingPrefix = ".omnimac-instalando-"

    /// ¿Es el nombre de una carpeta provisional de esta función? El prefijo y un UUID
    /// completo, nada más: lo que el usuario tenga con un nombre parecido no se toca.
    static func isStagingFolderName(_ name: String) -> Bool {
        guard name.hasPrefix(stagingPrefix) else { return false }
        let rest = String(name.dropFirst(stagingPrefix.count))
        return rest.count == 36 && UUID(uuidString: rest) != nil
    }

    /// Borra las carpetas provisionales que dejó una instalación que no llegó a su final
    /// (la app se cerró, se fue la luz) y devuelve sus nombres. Solo mira dentro de `folder`,
    /// y solo carpetas de verdad: un enlace con ese nombre no se sigue ni se toca.
    @discardableResult
    static func removeLeftovers(in folder: URL) -> [String] {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path) else { return [] }
        var removed: [String] = []
        for name in names where isStagingFolderName(name) {
            let url = folder.appending(path: name)
            guard ItemKind.of(url) == .folder else { continue }
            do {
                try files.removeItem(at: url)
                removed.append(name)
            } catch {
                continue   // sin permiso o en uso: se intentará en el próximo arranque
            }
        }
        return removed.sorted()
    }
}
