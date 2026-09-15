import Carbon.HIToolbox
import XCTest
@testable import OmniMac

/// El teclado del panel del portapapeles.
final class PanelKeyTests: XCTestCase {
    private func key(_ code: Int, _ flags: NSEvent.ModifierFlags = [], _ characters: String? = nil,
                     queryIsEmpty: Bool = true, itemCount: Int = 5) -> PanelKey {
        PanelKey.action(keyCode: code, flags: flags, characters: characters,
                        queryIsEmpty: queryIsEmpty, itemCount: itemCount)
    }

    /// Lo que costó el atajo viejo: con los números sueltos eligiendo elemento, no
    /// había forma de buscar «2026» ni ninguna cifra.
    func testUnNumeroSueltoSeEscribeEnElBuscador() {
        XCTAssertEqual(key(Int(kVK_ANSI_2), [], "2"), .type("2"))
    }

    func testConComandoElNumeroEligeElemento() {
        XCTAssertEqual(key(Int(kVK_ANSI_2), .command, "2"), .pick(1))
    }

    /// Y elegir por número vale también mientras buscas.
    func testElegirPorNumeroFuncionaBuscando() {
        XCTAssertEqual(key(Int(kVK_ANSI_3), .command, "3", queryIsEmpty: false), .pick(2))
    }

    /// Un número mayor que la lista no elige nada (ni pega el último por error).
    func testNumeroFueraDeLaLista() {
        XCTAssertEqual(key(Int(kVK_ANSI_9), .command, "9", itemCount: 3), .passThrough)
    }

    /// Esc limpia la búsqueda antes de cerrar: cerrar con algo escrito se siente
    /// como perder lo que estabas haciendo.
    func testEscapeLimpiaAntesDeCerrar() {
        XCTAssertEqual(key(Int(kVK_Escape), [], queryIsEmpty: false), .clearQuery)
        XCTAssertEqual(key(Int(kVK_Escape), [], queryIsEmpty: true), .close)
    }

    func testFlechasYEntrar() {
        XCTAssertEqual(key(Int(kVK_DownArrow)), .moveDown)
        XCTAssertEqual(key(Int(kVK_UpArrow)), .moveUp)
        XCTAssertEqual(key(Int(kVK_Return)), .paste)
    }

    func testAnclarYBorrarLlevanOpcion() {
        XCTAssertEqual(key(Int(kVK_ANSI_P), .option, "p"), .pin)
        XCTAssertEqual(key(Int(kVK_Delete), .option), .deleteItem)
        XCTAssertEqual(key(Int(kVK_Delete)), .backspace)
    }

    /// Una «p» a secas se busca, no ancla nada.
    func testLaPSinOpcionSeEscribe() {
        XCTAssertEqual(key(Int(kVK_ANSI_P), [], "p"), .type("p"))
    }

    /// Los atajos de otras apps (⌘C, ⌃algo) siguen su camino.
    func testLosAtajosAjenosPasan() {
        XCTAssertEqual(key(Int(kVK_ANSI_C), .command, "c"), .passThrough)
        XCTAssertEqual(key(Int(kVK_ANSI_A), .control, "a"), .passThrough)
    }

    func testLasTeclasSinTextoNoEscriben() {
        XCTAssertEqual(key(Int(kVK_F5), [], nil), .passThrough)
    }
}
