import XCTest
@testable import OmniMac

/// La parte de `CodeSignature` que no necesita una app firmada: qué se le pide a macOS para
/// dar por bueno un Team ID. Leer firmas de verdad es cosa de Security.framework y no hay
/// aquí una app de cada tipo; lo que sí se puede probar es que el texto del requisito no
/// admita nada que no sea un Team ID.
final class CodeSignatureTests: XCTestCase {

    func testTheRequirementTiesTheTeamToTheCertificate() {
        XCTAssertEqual(CodeSignature.requirementText(forTeam: "ABCDE12345"),
                       "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"")
    }

    func testRealTeamIdentifiersAreTenUppercaseLettersOrDigits() {
        for team in ["ABCDE12345", "0123456789", "ZZZZZZZZZZ", "A1B2C3D4E5"] {
            XCTAssertTrue(CodeSignature.isTeamIdentifier(team), team)
            XCTAssertNotNil(CodeSignature.requirementText(forTeam: team), team)
        }
    }

    func testAnythingElseNeverReachesTheRequirementText() {
        // El Team ID sale del propio código y acaba dentro de un requisito: lo que no tenga
        // su forma no pasa, y menos algo con comillas que cierre la cadena.
        for other in ["", "abcde12345", "ABCDE1234", "ABCDE123456", "ABCDE 1234", "ABCDE1234\n",
                      "ABCDE\"234", "\" or anchor apple", "ABCDE12345\" or \"1\" = \"1",
                      "ÁBCDE12345", "ABCDE-2345", "ABCDE1234]"] {
            XCTAssertFalse(CodeSignature.isTeamIdentifier(other), other)
            XCTAssertNil(CodeSignature.requirementText(forTeam: other), other)
        }
    }
}
