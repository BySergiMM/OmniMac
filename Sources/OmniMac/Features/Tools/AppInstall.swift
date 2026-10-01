import Foundation

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
        /// Quién firmó la app de esa ruta.
        var signer: (URL) -> AppSigner
        /// Manda algo a la papelera y dice dónde ha quedado.
        var trash: (URL) throws -> URL?
        var readQuarantine: (URL) -> String?
        /// `false` si no se pudo escribir.
        var writeQuarantine: (String, URL) -> Bool
    }

    enum Failure: Error, Equatable {
        case copyFailed(String)
        /// La copia no tiene la firma que se le enseñó al usuario.
        case signerChanged
        /// El `.dmg` estaba en cuarentena y no se ha podido dejar la copia igual: se
        /// prefiere no instalar a instalar saltándose la revisión de Gatekeeper.
        case quarantineNotApplied
        case replaceFailed(String)
    }

    /// Instala `source` (la app dentro del disco montado) en `folder` y devuelve dónde ha
    /// quedado.
    ///
    /// - `expecting`: el firmante que se le enseñó al usuario al pedirle permiso.
    /// - `imageQuarantine`: la marca del `.dmg` (`nil` si no la tenía).
    static func install(source: URL, into folder: URL, expecting: AppSigner,
                        imageQuarantine: String?, using environment: Environment) -> Result<URL, Failure> {
        let files = FileManager.default
        let name = source.lastPathComponent
        let target = folder.appending(path: name)

        // Provisional, en la misma carpeta que el destino: así el último paso es un
        // renombrado dentro del mismo volumen y no una segunda copia.
        let staging = folder.appending(path: ".omnimac-instalando-\(UUID().uuidString)")
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
        // Pase lo que pase, la carpeta provisional se va: la ha creado esta función y solo
        // contiene la copia.
        defer { try? files.removeItem(at: staging) }

        let staged = staging.appending(path: name)
        do {
            try files.copyItem(at: source, to: staged)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }

        // Se comprueba la copia, que es lo que se va a instalar, y no el disco: así lo que
        // se mira es exactamente lo que acaba en Aplicaciones.
        guard environment.signer(staged) == expecting else { return .failure(.signerChanged) }

        if let value = QuarantineMark.valueForCopy(image: imageQuarantine, app: environment.readQuarantine(staged)) {
            guard environment.writeQuarantine(value, staged) else { return .failure(.quarantineNotApplied) }
        }

        // Hasta aquí no se ha tocado nada de lo que ya había.
        var trashed: URL?
        if files.fileExists(atPath: target.path) {
            do {
                trashed = try environment.trash(target)
            } catch {
                return .failure(.replaceFailed(error.localizedDescription))
            }
        }
        do {
            try files.moveItem(at: staged, to: target)
        } catch {
            // Lo anterior vuelve a su sitio, si se puede.
            if let previous = trashed { try? files.moveItem(at: previous, to: target) }
            return .failure(.replaceFailed(error.localizedDescription))
        }
        return .success(target)
    }
}
