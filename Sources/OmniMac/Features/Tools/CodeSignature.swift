import Foundation
import Security

/// Lee quién firmó una app con Security.framework. Es el único sitio que habla con el
/// sistema para esto; lo que se decide con el resultado está en `InstallReview`.
enum CodeSignature {

    // `kSecCSSigningInformation` se escribe aquí con su valor en vez de importar el nombre:
    // es parte de su interfaz estable (SecCode.h) y así no depende de cómo se importe a Swift.

    /// `errSecCSUnsigned`: el objeto no lleva firma.
    private static let unsignedStatus: OSStatus = -67062
    /// `kSecCSSigningInformation`: pide los datos de la firma (entre ellos el Team ID).
    private static let signingInformation = SecCSFlags(rawValue: 1 << 1)

    /// Cómo se valida una firma para darla por buena, con las tres opciones que
    /// la documentación de `SecStaticCodeCheckValidity` y de «Static Code Validation Flags»
    /// pide para un paquete de verdad:
    /// - `kSecCSCheckAllArchitectures`: en un binario universal, todas las rebanadas. Sin
    ///   esto se comprueba una sola y las demás pueden venir sin firma o con otra.
    /// - `kSecCSCheckNestedCode`: el código de dentro (frameworks, ayudantes, extensiones).
    /// - `kSecCSStrictValidate`: comprobaciones extra de que el paquete no está montado de
    ///   forma que permita manipularlo.
    private static let validation = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    /// El requisito que ata un Team ID a un certificado de Apple de verdad: la cadena
    /// del certificado llega a una raíz de Apple **y** el certificado de quien firma lleva ese
    /// Team ID en su campo OU. Sin la segunda mitad, el Team ID sería lo que el código dice
    /// de sí mismo, y cualquiera con una firma suya de Apple podría escribir el de otro.
    ///
    /// Devuelve `nil` si lo que llega no tiene forma de Team ID (10 letras mayúsculas o
    /// cifras): el texto acaba dentro de un requisito, y no se le cuela nada que no lo sea.
    ///
    /// Ojo: «anchor apple generic» también lo cumplen los certificados de desarrollo
    /// (Apple Development), no solo los de Developer ID o de la App Store, así que esto dice
    /// *quién* firmó, no que haya pasado por la notarización. De eso se ocupa Gatekeeper al
    /// abrirla, y por eso se conserva la cuarentena.
    static func requirementText(forTeam team: String) -> String? {
        guard isTeamIdentifier(team) else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    static func isTeamIdentifier(_ text: String) -> Bool {
        text.utf8.count == 10 && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) }
    }

    static func signer(of app: URL) -> AppSigner {
        var created: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &created) == errSecSuccess,
              let code = created else {
            // Ni se puede leer como una app: no hay nada de lo que fiarse.
            return .broken
        }

        // 1. ¿Tiene firma, y casa con el contenido? Sin pedir ningún firmante en concreto.
        let validity = SecStaticCodeCheckValidity(code, validation, nil)
        if validity == unsignedStatus { return .unsigned }
        guard validity == errSecSuccess else { return .broken }

        // 2. El Team ID que dice llevar el código.
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, signingInformation, &information) == errSecSuccess,
              let details = information as? [String: Any],
              let team = details[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else {
            // Firma intacta pero sin Team ID: ad-hoc, autofirmada, o de Apple (las apps del
            // sistema). No hay con qué comparar.
            return .unverified
        }

        // 3. Que ese Team ID sea el del certificado de Apple con el que se firmó, no solo lo
        //    que el código afirma.
        var requirement: SecRequirement?
        guard let text = requirementText(forTeam: team),
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let bound = requirement,
              SecStaticCodeCheckValidity(code, validation, bound) == errSecSuccess else {
            return .unverified
        }
        return .team(team)
    }
}

/// La marca `com.apple.quarantine` de un archivo o carpeta. Qué se hace con ella lo decide
/// `QuarantineMark`; esto solo la lee y la escribe.
enum QuarantineAttribute {

    static func read(at url: URL) -> String? {
        let name = QuarantineMark.attribute
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let count = getxattr(url.path, name, &buffer, size, 0, 0)
        guard count > 0 else { return nil }
        return String(decoding: buffer.prefix(count), as: UTF8.self)
    }

    /// `false` si no se pudo escribir.
    static func write(_ value: String, at url: URL) -> Bool {
        let bytes = Array(value.utf8)
        return setxattr(url.path, QuarantineMark.attribute, bytes, bytes.count, 0, 0) == 0
    }
}

extension AppInstall.Environment {
    /// Las comprobaciones de verdad, contra el sistema.
    static var live: AppInstall.Environment {
        AppInstall.Environment(
            identity: { app in
                // Sin huella no hay identidad: no coincidirá con nada.
                guard let digest = AppDigest.of(app) else { return nil }
                return AppIdentity(signer: CodeSignature.signer(of: app), digest: digest)
            },
            trash: { url in
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                return result as URL?
            },
            readQuarantine: { QuarantineAttribute.read(at: $0) },
            writeQuarantine: { QuarantineAttribute.write($0, at: $1) }
        )
    }
}
