import XCTest
@testable import OmniMac

/// El buscador de comandos. Lo que se prueba aquí es lo único que decide si el
/// panel se siente listo o tonto: qué sale primero.
final class CommandMatcherTests: XCTestCase {
    func testFindsLettersInOrderEvenIfScattered() {
        // «slmi» debe encontrar «Silenciar el micrófono»
        XCTAssertNotNil(CommandMatcher.score("Silenciar el micrófono", query: "slmi"))
    }

    func testRejectsLettersOutOfOrder() {
        XCTAssertNil(CommandMatcher.score("Silenciar", query: "isl"))
    }

    func testIgnoresAccentsAndCase() {
        XCTAssertNotNil(CommandMatcher.score("Micrófono", query: "MICROFONO"))
        XCTAssertNotNil(CommandMatcher.score("Micrófono", query: "micro"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertEqual(CommandMatcher.score("lo que sea", query: ""), 0)
    }

    /// El caso que motivó la puntuación: «mic» tenía que dar «Micrófono», no
    /// «Historial del portapapeles» (que también tiene m, i y c sueltas).
    func testStartOfWordBeatsScatteredLetters() {
        let direct = CommandMatcher.score("Micrófono", query: "mic")!
        let scattered = CommandMatcher.score("Historial del portapapeles", query: "mic") ?? -1_000
        XCTAssertGreaterThan(direct, scattered)
    }

    func testPrefixBeatsMiddle() {
        let prefix = CommandMatcher.score("Sonido", query: "son")!
        let middle = CommandMatcher.score("Cambiar de sonido", query: "son")!
        XCTAssertGreaterThan(prefix, middle)
    }

    /// Con el mismo encaje, gana el nombre corto: quien busca «ajustes» quiere
    /// «Ajustes», no «Ajustes avanzados de red».
    func testShorterWins() {
        let short = CommandMatcher.score("Ajustes", query: "ajustes")!
        let long = CommandMatcher.score("Ajustes avanzados de red y proxy", query: "ajustes")!
        XCTAssertGreaterThan(short, long)
    }

    func testRankingOrdersAndCuts() {
        let names = ["Micrófono", "Historial del portapapeles", "Mantener despierto", "Mail"]
        let ranked = CommandMatcher.rank(names, query: "mi", limit: 2) { $0 }
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first, "Micrófono")
    }

    func testRankingDropsWhatDoesNotMatch() {
        XCTAssertTrue(CommandMatcher.rank(["Sonido"], query: "zzz") { $0 }.isEmpty)
    }

    /// El fallo que hacía que el buscador pareciera tonto: escribir el nombre de una
    /// app y que Intro ejecutara un comando que solo comparte letras sueltas.
    func testWhatIsWrittenAsIsWins() {
        let app = CommandMatcher.score("Mail abrir open launch app", query: "mail")!
        let scattered = CommandMatcher.score("Mantener el Mac despierto cafe dormir sleep", query: "mail")!
        XCTAssertGreaterThan(app, scattered)
    }

    /// Y además lo que apenas encaja ni se enseña, aunque sobre sitio en la lista.
    func testRankingDropsWhatBarelyMatches() {
        let ranked = CommandMatcher.rank(["Mail", "Mantener el Mac despierto"], query: "mail") { $0 }
        XCTAssertEqual(ranked, ["Mail"])
    }

    /// A igualdad de encaje gana lo de OmniMac, que es de lo que va el buscador.
    func testTheBonusOnlyDecidesTies() {
        struct Item: Equatable { let name: String; let isApp: Bool }
        let items = [Item(name: "Sonido", isApp: true), Item(name: "Sonido", isApp: false)]
        let ranked = CommandMatcher.rank(items, query: "son", bonus: { $0.isApp ? 0 : 6 }) { $0.name }
        XCTAssertEqual(ranked.first?.isApp, false)
    }

    /// Un punto de más no puede dejar la búsqueda en «Nada que coincida».
    func testPunctuationDoesNotBreakTheSearch() {
        XCTAssertNotNil(CommandMatcher.score("Micrófono", query: "mic."))
        XCTAssertEqual(CommandMatcher.normalize("  Mic.  "), "mic")
        XCTAssertEqual(CommandMatcher.normalize("a-b"), "a b")
    }
}
