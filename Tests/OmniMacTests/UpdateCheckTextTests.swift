import XCTest
@testable import OmniMac

/// «Última comprobación» de Ajustes: la fecha relativa sale en el idioma de la frase.
final class UpdateCheckTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var twoHoursAgo: Date { now.addingTimeInterval(-2 * 3600) }

    func testEnglishSentenceCarriesAnEnglishDate() {
        // Es el fallo de origen: el formateador llevaba siempre `es_ES` y la frase
        // en inglés acababa en «hace 2 horas».
        let text = UpdateCheckText.lastCheck(twoHoursAgo, now: now, spanish: false)
        XCTAssertTrue(text.hasPrefix("Last check: "), text)
        XCTAssertTrue(text.contains("ago"), text)
        XCTAssertFalse(text.contains("hace"), text)
    }

    func testSpanishSentenceCarriesASpanishDate() {
        let text = UpdateCheckText.lastCheck(twoHoursAgo, now: now, spanish: true)
        XCTAssertTrue(text.hasPrefix("Última comprobación: "), text)
        XCTAssertTrue(text.contains("hace"), text)
        XCTAssertFalse(text.contains("ago"), text)
    }

    func testNeverCheckedYet() {
        XCTAssertEqual(UpdateCheckText.lastCheck(nil, now: now, spanish: false), "Not checked yet")
        XCTAssertEqual(UpdateCheckText.lastCheck(nil, now: now, spanish: true), "Aún no se ha comprobado")
    }

    func testTheDateIsRelativeToTheGivenNow() {
        // Con otro «ahora» la misma fecha cambia de distancia: no se lee el reloj por dentro.
        let later = now.addingTimeInterval(3 * 24 * 3600)
        let soon = UpdateCheckText.lastCheck(twoHoursAgo, now: now, spanish: false)
        let far = UpdateCheckText.lastCheck(twoHoursAgo, now: later, spanish: false)
        XCTAssertNotEqual(soon, far)
    }
}
