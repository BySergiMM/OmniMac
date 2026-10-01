import Foundation
import Security

/// Lee quién firmó una app con Security.framework. Es el único sitio que habla con el
/// sistema para esto; lo que se decide con el resultado está en `InstallReview`.
enum CodeSignature {

    // Los valores de Security que se usan, escritos aquí en vez de importar sus nombres:
    // son parte de su interfaz estable y así no depende de cómo se importen a Swift.

    /// `errSecCSUnsigned`: el objeto no lleva firma.
    private static let unsignedStatus: OSStatus = -67062
    /// `kSecCSSigningInformation`: pide los datos de la firma (entre ellos el Team ID).
    private static let signingInformation = SecCSFlags(rawValue: 1 << 1)

    /// Solo se da por bueno un Team ID si la firma está entera **y** cuelga de una
    /// autoridad de Apple: «anchor apple generic». Sin esa condición, quien quisiera se
    /// haría pasar por otro desarrollador con una firma autofirmada que repita su Team ID.
    private static let appleAnchored = "anchor apple generic"

    static func signer(of app: URL) -> AppSigner {
        var created: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &created) == errSecSuccess,
              let code = created else {
            // Ni se puede leer como una app: no hay nada de lo que fiarse.
            return .broken
        }

        // 1. ¿Tiene firma, y casa con el contenido? Sin pedir ningún firmante en concreto.
        let validity = SecStaticCodeCheckValidity(code, [], nil)
        if validity == unsignedStatus { return .unsigned }
        guard validity == errSecSuccess else { return .broken }

        // 2. ¿La hizo alguien con certificado de Apple?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(appleAnchored as CFString, [], &requirement) == errSecSuccess,
              let anchored = requirement,
              SecStaticCodeCheckValidity(code, [], anchored) == errSecSuccess else {
            return .unverified
        }

        // 3. Y su Team ID, que es el que va en el certificado.
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, signingInformation, &information) == errSecSuccess,
              let details = information as? [String: Any],
              let team = details[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else {
            // Firmada por Apple pero sin Team ID (las apps del sistema): no hay con qué comparar.
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
            signer: { CodeSignature.signer(of: $0) },
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
