import XCTest
@testable import OmniMac

final class SystemTextTests: XCTestCase {

    func testRepairsTheRealCase() {
        // Tal cual lo devuelve macOS para el servicio de máquina virtual de Claude.
        XCTAssertEqual(SystemText.repaired("Servicio de la m√°quina virtual para Claude"),
                       "Servicio de la máquina virtual para Claude")
    }

    func testRepairsEveryCommonAccent() {
        XCTAssertEqual(SystemText.repaired("Caf√©"), "Café")
        XCTAssertEqual(SystemText.repaired("Espa√±a"), "España")
        XCTAssertEqual(SystemText.repaired("M√ºnchen"), "München")
        XCTAssertEqual(SystemText.repaired("Fran√ßais"), "Français")
        XCTAssertEqual(SystemText.repaired("a ¬∑ b"), "a · b")
    }

    func testRepairsTypographicPunctuation() {
        XCTAssertEqual(SystemText.repaired("It‚Äôs"), "It’s")
    }

    func testLeavesCorrectTextAlone() {
        // Lo importante no es arreglar lo roto: es no romper lo que está bien.
        for ok in ["Café", "España", "máquina virtual", "München", "Google Chrome",
                   "claude", "a · b", "It’s", "日本語", "🎧 Música", "WindowServer"] {
            XCTAssertEqual(SystemText.repaired(ok), ok, "tocó un texto que estaba bien: \(ok)")
        }
    }

    func testLeavesARealSquareRootAlone() {
        // Lleva la marca, pero sus bytes en MacRoman no son UTF-8: no era este error.
        XCTAssertEqual(SystemText.repaired("√2 Calculator"), "√2 Calculator")
    }

    func testRepairingTwiceChangesNothing() {
        let once = SystemText.repaired("m√°quina")
        XCTAssertEqual(SystemText.repaired(once), once)
    }
}
