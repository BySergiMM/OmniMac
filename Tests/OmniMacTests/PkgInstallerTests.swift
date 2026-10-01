import XCTest
@testable import OmniMac

/// El instalador `.pkg`: qué texto enseña en cada idioma y lo que **no** hace. Se lee
/// de `scripts/pkg`, porque `productbuild` solo corre en un Mac con el paquete ya
/// compilado y esto es lo que se puede comprobar antes de publicarlo.
final class PkgInstallerTests: XCTestCase {
    private let pkgDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/pkg")

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: pkgDirectory.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// El script sin sus comentarios: los comentarios sí pueden nombrar la regla (para
    /// explicar por qué no se instala); el código no.
    private func postinstallCode() throws -> String {
        try read("postinstall")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }

    // MARK: - Lo que no hace

    func testThePostinstallInstallsNoAdministratorRule() throws {
        let code = try postinstallCode()
        for forbidden in ["sudoers", "visudo", "NOPASSWD", "%admin"] {
            XCTAssertFalse(code.contains(forbidden), "el postinstall menciona «\(forbidden)»:\n\(code)")
        }
    }

    func testThePostinstallOnlyEverTurnsDisableSleepOff() throws {
        // Es lo único que toca del sistema: dejar el valor normal por si una sesión
        // anterior lo dejó puesto. Nunca lo enciende.
        let code = try postinstallCode()
        XCTAssertTrue(code.contains("/usr/bin/pmset -a disablesleep 0"), code)
        XCTAssertFalse(code.contains("disablesleep 1"), code)
    }

    func testThePostinstallIsValidShell() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", pkgDirectory.appendingPathComponent("postinstall").path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    // MARK: - Los textos

    func testWelcomeAndConclusionExistInBothLanguages() throws {
        for language in ["en", "es"] {
            for name in ["welcome.txt", "conclusion.txt"] {
                let text = try read("resources/\(language).lproj/\(name)")
                XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language).lproj/\(name) está vacío")
            }
        }
    }

    func testNoUnlocalizedCopyShadowsTheTranslations() {
        // Al buscar un recurso se mira antes el de la raíz que el de un `.lproj`: con
        // una copia suelta, todos verían ese idioma y las traducciones no se usarían nunca.
        for name in ["welcome.txt", "conclusion.txt"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: pkgDirectory.appendingPathComponent("resources/\(name)").path),
                           "resources/\(name) tapa a las versiones de los .lproj")
        }
    }

    func testTheDistributionPointsAtTheSameFileNames() throws {
        let distribution = try read("distribution.xml.in")
        XCTAssertTrue(distribution.contains("file=\"welcome.txt\""))
        XCTAssertTrue(distribution.contains("file=\"conclusion.txt\""))
    }

    func testTheTextsSayThePackageInstallsNoRule() throws {
        let es = try read("resources/es.lproj/welcome.txt")
        let en = try read("resources/en.lproj/welcome.txt")
        XCTAssertTrue(es.contains("No instala ninguna regla de administrador"), es)
        XCTAssertTrue(en.contains("Does not install any administrator rule"), en)
        // Y que el modo viene apagado, que es lo que explican las dos conclusiones.
        let esEnd = try read("resources/es.lproj/conclusion.txt")
        let enEnd = try read("resources/en.lproj/conclusion.txt")
        XCTAssertTrue(esEnd.contains("viene apagado"), esEnd)
        XCTAssertTrue(enEnd.contains("off by default"), enEnd)
    }

    func testEachLanguageStaysInItsOwn() throws {
        for name in ["welcome.txt", "conclusion.txt"] {
            let es = try read("resources/es.lproj/\(name)")
            let en = try read("resources/en.lproj/\(name)")
            XCTAssertFalse(es.contains("administrator"), "es.lproj/\(name) tiene inglés")
            XCTAssertFalse(en.contains("administrador"), "en.lproj/\(name) tiene español")
        }
    }
}
