import Foundation

/// Quién firmó una app, tal y como lo cuenta macOS. Es lo que se decide al instalar desde
/// un `.dmg`.
///
/// Leer la firma es cosa de `CodeSignature`. Aquí no hay nada del sistema, para poder
/// probar todas las combinaciones sin tener a mano una app firmada de cada manera.
enum AppSigner: Equatable {
    /// Firma intacta y hecha con un certificado que cuelga de Apple. Solo en este caso
    /// vale algo el Team ID: una firma autofirmada puede decir el que quiera.
    case team(String)
    /// Firma intacta, pero sin certificado de Apple (ad-hoc o autofirmada): no se sabe
    /// quién la hizo.
    case unverified
    case unsigned
    /// Trae firma, pero no cuadra con el contenido: la han tocado o está dañada.
    case broken
}

/// Qué es exactamente la app que se le enseñó al usuario: quién la firmó **y** qué hay dentro.
///
/// El firmante solo no basta para reconocer «la misma app». Dos apps sin firma (o con firma
/// ad-hoc) son para `AppSigner` la misma cosa (`.unsigned`, `.unverified`) aunque no tengan
/// nada que ver, y entre el primer aviso y la copia el `.dmg` puede haber cambiado: está en
/// Descargas, donde escribe cualquier programa del usuario. La huella del contenido es lo
/// que ata lo que se revisó con lo que se instala.
struct AppIdentity: Equatable {
    let signer: AppSigner
    /// SHA-256 en hexadecimal de todo el paquete. Lo calcula `AppDigest`.
    let digest: String
}

/// Lo que se concluye de comparar la app nueva con la que ya hubiera en su sitio.
enum InstallVerdict: Equatable {
    /// No había ninguna: solo se enseña de quién es.
    case firstInstall(team: String)
    /// Sustituye a una del mismo Team ID.
    case sameDeveloper(team: String)
    /// Sustituye a una de **otro** Team ID.
    case differentDeveloper(new: String, installed: String)
    /// Sustituye a una cuyo firmante no se puede comprobar, así que no hay forma de saber
    /// si es el mismo desarrollador.
    case installedNotComparable(new: String, installed: AppSigner)
    /// La nueva no trae una firma de la que fiarse (sin firma, o sin certificado de Apple).
    case incomingNotTrusted(AppSigner, replacing: Bool)
    /// La firma está rota: no se instala.
    case brokenSignature

    enum Severity: Equatable {
        /// Se muestra de quién es y se pregunta.
        case fine
        /// Se avisa, y el botón por defecto es no instalar.
        case warning
        /// No se instala.
        case refused
    }

    var severity: Severity {
        switch self {
        case .firstInstall, .sameDeveloper:
            return .fine
        case .differentDeveloper, .installedNotComparable, .incomingNotTrusted:
            return .warning
        case .brokenSignature:
            return .refused
        }
    }
}

/// La confirmación que se le enseña al usuario antes de copiar nada: el veredicto, y los
/// textos y botones que salen de él.
///
/// Los textos reciben el idioma por parámetro (en la app, `Localization.isSpanish`, que es
/// lo que usa `L`) para probar los dos sin depender del Mac donde corra la prueba. Es el
/// mismo patrón que `ClosedLidRule` y `UpdateCheckText`.
enum InstallReview {

    // MARK: - El veredicto

    /// `installed` es `nil` si en el destino no hay ninguna app con ese nombre.
    ///
    /// Solo se da por «el mismo desarrollador» cuando **los dos** Team ID son de Apple y
    /// coinciden. Cualquier otra cosa en la app que se va a sustituir (sin firma, ad-hoc,
    /// rota) se avisa: no hay con qué compararla.
    static func verdict(incoming: AppSigner, installed: AppSigner?) -> InstallVerdict {
        switch incoming {
        case .broken:
            return .brokenSignature
        case .unsigned, .unverified:
            return .incomingNotTrusted(incoming, replacing: installed != nil)
        case .team(let new):
            guard let installed = installed else { return .firstInstall(team: new) }
            switch installed {
            case .team(let old):
                return old == new
                    ? .sameDeveloper(team: new)
                    : .differentDeveloper(new: new, installed: old)
            case .unverified, .unsigned, .broken:
                return .installedNotComparable(new: new, installed: installed)
            }
        }
    }

    // MARK: - Los botones

    struct Buttons: Equatable {
        /// En el orden en que se añaden al aviso: el primero es el que se activa con Intro.
        let titles: [String]
        /// Cuál de ellos instala. `nil` si ninguno: una firma rota no se instala.
        let installIndex: Int?
    }

    /// Con un aviso, el botón por defecto es **no instalar**: que un Intro por reflejo no
    /// sea lo que deje pasar la app.
    static func buttons(for verdict: InstallVerdict, spanish: Bool) -> Buttons {
        switch verdict.severity {
        case .fine:
            return Buttons(titles: [spanish ? "Instalar" : "Install",
                                    spanish ? "Cancelar" : "Cancel"],
                           installIndex: 0)
        case .warning:
            return Buttons(titles: [spanish ? "No instalar" : "Don’t install",
                                    spanish ? "Instalar igualmente" : "Install anyway"],
                           installIndex: 1)
        case .refused:
            return Buttons(titles: [spanish ? "Entendido" : "OK"], installIndex: nil)
        }
    }

    // MARK: - Los textos

    /// `app` es el nombre sin «.app».
    static func title(app: String, verdict: InstallVerdict, spanish: Bool) -> String {
        switch verdict {
        case .firstInstall:
            return spanish ? "¿Instalar \(app)?" : "Install \(app)?"
        case .sameDeveloper:
            return spanish ? "¿Actualizar \(app)?" : "Update \(app)?"
        case .differentDeveloper:
            return spanish ? "\(app): la firma otro desarrollador" : "\(app): signed by a different developer"
        case .installedNotComparable:
            return spanish ? "\(app): no se puede comprobar el desarrollador" : "\(app): can’t check the developer"
        case .incomingNotTrusted:
            return spanish ? "\(app): sin una firma de confianza" : "\(app): no trusted signature"
        case .brokenSignature:
            return spanish ? "No se instala \(app)" : "\(app) won’t be installed"
        }
    }

    /// `folder` es la carpeta donde se copiaría.
    static func message(app: String, verdict: InstallVerdict, folder: String, spanish: Bool) -> String {
        switch verdict {
        case .firstInstall(let team):
            return spanish
                ? "Firmada por el Team ID \(team): el certificado es de Apple y la firma está intacta. Eso dice quién la firmó, no que sea de fiar; compáralo con el que publica el desarrollador.\n\nSe copiará a \(folder) y el .dmg irá a la papelera."
                : "Signed by Team ID \(team): the certificate is Apple-issued and the signature is intact. That says who signed it, not that they can be trusted; compare it with the one the developer publishes.\n\nIt will be copied to \(folder) and the .dmg moved to the Trash."
        case .sameDeveloper(let team):
            return spanish
                ? "Firmada por el mismo Team ID (\(team)) que la versión que ya tienes. La versión actual irá a la papelera, la nueva se copiará a \(folder) y el .dmg también irá a la papelera."
                : "Signed by the same Team ID (\(team)) as the version you have. The current version will go to the Trash, the new one will be copied to \(folder), and the .dmg will go to the Trash too."
        case .differentDeveloper(let new, let installed):
            return spanish
                ? "La app que tienes está firmada por el Team ID \(installed) y la nueva, por el \(new). Puede ser legítimo, si el desarrollador cambió de cuenta, pero también es lo que haría una app falsa que se hace pasar por la tuya. Si no estás seguro, no la instales.\n\n" + replaceNote(spanish: true)
                : "The app you have is signed by Team ID \(installed) and the new one by \(new). That can be legitimate if the developer changed accounts, but it is also what a fake app pretending to be yours would look like. If you’re not sure, don’t install it.\n\n" + replaceNote(spanish: false)
        case .installedNotComparable(let new, let installed):
            let state = describe(installed, spanish: spanish)
            return spanish
                ? "La nueva está firmada por el Team ID \(new), pero la que tienes \(state), así que no se puede comprobar que sean del mismo desarrollador. Si no estás seguro, no la instales.\n\n" + replaceNote(spanish: true)
                : "The new one is signed by Team ID \(new), but the one you have \(state), so there’s no way to check they come from the same developer. If you’re not sure, don’t install it.\n\n" + replaceNote(spanish: false)
        case .incomingNotTrusted(let signer, let replacing):
            let why = signer == .unsigned
                ? (spanish ? "No está firmada: no hay forma de saber quién la hizo ni si la han modificado."
                           : "It isn’t signed: there’s no way to know who made it or whether it was modified.")
                : (spanish ? "Su firma no lleva un certificado de Apple (es ad-hoc o autofirmada): no hay un Team ID en el que fiarse."
                           : "Its signature has no Apple certificate (it’s ad-hoc or self-signed): there’s no Team ID to rely on.")
            let advice = spanish ? " Si no estás seguro, no la instales." : " If you’re not sure, don’t install it."
            let ending = replacing
                ? replaceNote(spanish: spanish)
                : (spanish ? "Se copiará a \(folder)." : "It will be copied to \(folder).")
            return why + advice + "\n\n" + ending
        case .brokenSignature:
            return spanish
                ? "Su firma no pasa la comprobación estricta de macOS: no coincide con su contenido o está mal formada (la han modificado, o el archivo está dañado). OmniMac no la instala y deja el .dmg donde está."
                : "Its signature doesn’t pass macOS’s strict check: it doesn’t match its contents or is malformed (it was modified, or the file is damaged). OmniMac won’t install it and leaves the .dmg where it is."
        }
    }

    private static func replaceNote(spanish: Bool) -> String {
        spanish ? "Si continúas, la que tienes irá a la papelera."
                : "If you continue, the one you have goes to the Trash."
    }

    /// Cómo está la app instalada, para completar la frase «…pero la que tienes ___».
    private static func describe(_ signer: AppSigner, spanish: Bool) -> String {
        switch signer {
        case .team(let team):
            return spanish ? "está firmada por el Team ID \(team)" : "is signed by Team ID \(team)"
        case .unverified:
            return spanish ? "tiene una firma sin certificado de Apple (ad-hoc o autofirmada)"
                           : "has a signature without an Apple certificate (ad-hoc or self-signed)"
        case .unsigned:
            return spanish ? "no está firmada" : "isn’t signed"
        case .broken:
            return spanish ? "tiene la firma dañada" : "has a damaged signature"
        }
    }
}

/// La marca de «descargado de Internet» (`com.apple.quarantine`) y qué hacer con ella al
/// sacar una app de un `.dmg`.
///
/// Es la marca que hace que Gatekeeper revise la app la primera vez que se abre. Copiar la
/// app sin ella saltaría esa revisión, así que **nunca se quita**. Si el sistema no la pasa
/// solo del `.dmg` a la copia (no está comprobado que lo haga), se pone aquí.
///
/// **Apple no documenta las banderas** del valor (las cuatro primeras cifras, en hexadecimal).
/// Lo que sigue es lo que cuentan quienes lo han observado, no una garantía de Apple, y por
/// eso se toca lo mínimo:
///
/// - `0x0040`: el usuario ya aprobó la app en el aviso de la primera vez; macOS se la salta
///   desde entonces. Es lo único que se **quita**: la aprobación del usuario era para el
///   `.dmg`, no para lo que lleva dentro.
/// - `0x0100`: la app ya no está donde llegó (la han movido o copiado). Mientras falta,
///   macOS ejecuta la app «translocada», desde una copia de solo lectura en una ruta
///   aleatoria, y una app así no puede actualizarse sola. Es lo que pasa tras arrastrarla a
///   Aplicaciones con el Finder, así que se **añade** a la que escribe OmniMac, que es
///   justo una app copiada fuera del disco. No afecta a la revisión de Gatekeeper.
///   (Fuentes: Howard Oakley en eclecticlight.co, 2022-09-09, que ve `0083` al descargar y
///   `01c3` tras la primera apertura y el movimiento; y jwwalker.com/pages/quarantine.md.html.
///   El `SecTranslocate.h` de Apple nombra `QTN_FLAG_DO_NOT_TRANSLOCATE`, pero el número está
///   en una cabecera privada.) Hay que mirar en un Mac que la app instalada así no
///   se translocó; ver docs/RELEASE.md.
///
/// La API pública (`NSURLQuarantinePropertiesKey`) no sirve para esto: no tiene banderas,
/// solo agente, fecha y origen, y generaría un registro nuevo en vez de conservar el del
/// navegador (que es el que Gatekeeper enseña en su aviso).
enum QuarantineMark {
    static let attribute = "com.apple.quarantine"

    /// «El usuario ya lo ha aprobado».
    static let userApprovedFlag: UInt32 = 0x0040
    /// «Ya no está donde llegó».
    static let movedFlag: UInt32 = 0x0100

    /// El valor que hay que escribir en la app copiada, o `nil` si no hay nada que hacer.
    ///
    /// - `image`: lo que tiene el `.dmg` (`nil` si no estaba en cuarentena: no hay nada
    ///   que conservar).
    /// - `app`: lo que ya tiene la copia.
    ///
    /// Si la copia ya viene marcada (el sistema se la pasó del `.dmg` al copiar), es la marca
    /// que puso el sistema y se respeta entera, salvo la aprobación: un `.dmg` aprobado
    /// por el usuario no aprueba la app de dentro. Si no trae aprobación, no se escribe nada.
    static func valueForCopy(image: String?, app: String?) -> String? {
        if let app = app, !app.isEmpty {
            guard let bits = flags(of: app), bits & userApprovedFlag != 0 else { return nil }
            return withoutApproval(app)
        }
        guard let image = image, !image.isEmpty else { return nil }
        return markedAsMoved(withoutApproval(image))
    }

    /// El mismo valor sin el bit de «aprobado». Si el `.dmg` ya lo llevaba (porque alguien
    /// lo aprobó al abrirlo), copiarlo tal cual dejaría la app aprobada de antemano, sin que
    /// Gatekeeper la mire.
    ///
    /// Un valor que no se entiende se deja igual: sigue siendo una marca de cuarentena, que
    /// es lo que importa.
    static func withoutApproval(_ value: String) -> String {
        rewriting(value) { $0 & ~userApprovedFlag }
    }

    /// El mismo valor con el bit de «ya no está donde llegó». Igual que arriba, un valor que
    /// no se entiende se deja como está.
    static func markedAsMoved(_ value: String) -> String {
        rewriting(value) { $0 | movedFlag }
    }

    /// Las banderas de un valor, o `nil` si no se entienden.
    static func flags(of value: String) -> UInt32? {
        guard let first = value.split(separator: ";", omittingEmptySubsequences: false).first else { return nil }
        return UInt32(first, radix: 16)
    }

    private static func rewriting(_ value: String, _ change: (UInt32) -> UInt32) -> String {
        var parts = value.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        guard let bits = flags(of: value) else { return value }
        let hex = String(change(bits), radix: 16)
        // Cuatro cifras, como las escribe el sistema: «0081», no «81».
        parts[0] = String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        return parts.joined(separator: ";")
    }
}
