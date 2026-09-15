import XCTest
@testable import OmniMac

/// El lector del CHANGELOG y la regla de cuándo se enseñan las novedades.
final class ReleaseNotesTests: XCTestCase {
    private let sample = """
    # Cambios

    ## 0.4.2 — 2026-09-06

    - Ajustes › Inicio › Almacenamiento: muestra lo que ocupa la app.
    - La caché web queda acotada a **16 MB** en disco.

    ## 0.4.1 — 2026-09-05

    - Notch: el tap de clics se invalida al plegar.

    ## 0.3.0 — 2026-09-04

    **Nuevo**
    - Notch: pestañas Calendario y Sonido.
    - Instalación con `brew install --cask`.
    """

    func testReadsEveryVersionNewestFirst() {
        let all = ReleaseNotes.all(from: sample)
        XCTAssertEqual(all.map(\.version), ["0.4.2", "0.4.1", "0.3.0"])
    }

    func testReadsTheDate() {
        XCTAssertEqual(ReleaseNotes.notes(for: "0.4.2", in: sample)?.date, "2026-09-06")
    }

    func testReadsTheItemsOfOneVersion() {
        let notes = ReleaseNotes.notes(for: "0.4.1", in: sample)
        XCTAssertEqual(notes?.items, ["Notch: el tap de clics se invalida al plegar."])
    }

    func testStripsMarkdownWeCannotDraw() {
        let notes = ReleaseNotes.notes(for: "0.4.2", in: sample)
        XCTAssertEqual(notes?.items.last, "La caché web queda acotada a 16 MB en disco.")
        let old = ReleaseNotes.notes(for: "0.3.0", in: sample)
        XCTAssertEqual(old?.items.last, "Instalación con brew install --cask.")
    }

    func testIgnoresBoldSubheadings() {
        XCTAssertEqual(ReleaseNotes.notes(for: "0.3.0", in: sample)?.items.count, 2)
    }

    func testUnknownVersionHasNoNotes() {
        XCTAssertNil(ReleaseNotes.notes(for: "9.9.9", in: sample))
    }

    func testLinksKeepOnlyTheirText() {
        let markdown = "## 1.0\n\n- Ver el [estudio de consumo](docs/PERFORMANCE.md) completo.\n"
        XCTAssertEqual(ReleaseNotes.notes(for: "1.0", in: markdown)?.items.first,
                       "Ver el estudio de consumo completo.")
    }

    // MARK: - Cuándo se enseñan

    func testShownAfterAnUpdate() {
        XCTAssertTrue(ReleaseNotes.shouldShow(current: "0.4.3", lastSeen: "0.4.2"))
    }

    func testNotShownTwiceForTheSameVersion() {
        XCTAssertFalse(ReleaseNotes.shouldShow(current: "0.4.3", lastSeen: "0.4.3"))
    }

    func testNotShownOnAFreshInstall() {
        // Recién instalada sale la bienvenida; dos ventanas seguidas sobran.
        XCTAssertFalse(ReleaseNotes.shouldShow(current: "0.4.3", lastSeen: nil))
        XCTAssertFalse(ReleaseNotes.shouldShow(current: "0.4.3", lastSeen: ""))
    }
}

/// Las pantallas del recorrido que se arma con las novedades.
final class WhatsNewHighlightTests: XCTestCase {
    private func notes(_ items: String) -> ReleaseNotes {
        ReleaseNotes.notes(for: "1.0", in: "## 1.0\n\n\(items)")!
    }

    func testSplitsAreaAndDetail() {
        let h = notes("- Notch: ahora se adapta a cualquier Mac.\n").highlights.first
        XCTAssertEqual(h?.title, "Notch")
        XCTAssertEqual(h?.detail, "Ahora se adapta a cualquier Mac.")
    }

    func testAVeryLongTitleIsNotATitle() {
        // Si lo de antes de los dos puntos es una frase entera, no sirve de titular.
        let line = "- Con la ventana abierta y el ratón encima de las opciones: iba lento.\n"
        let h = notes(line).highlights.first
        XCTAssertNotEqual(h?.title, "Con la ventana abierta y el ratón encima de las opciones")
        XCTAssertTrue(h?.detail.contains("iba lento") ?? false)
    }

    func testPicksAnIconThatFitsTheSubject() {
        XCTAssertEqual(ReleaseNotes.symbol(for: "Notch: nueva pestaña"), "sparkles.rectangle.stack")
        XCTAssertEqual(ReleaseNotes.symbol(for: "Sonido: ecualizador de 10 bandas"), "slider.vertical.3")
        XCTAssertEqual(ReleaseNotes.symbol(for: "Portapapeles: búsqueda"), "doc.on.clipboard")
        XCTAssertEqual(ReleaseNotes.symbol(for: "Algo sin asunto conocido"), "sparkles")
    }

    func testOneScreenPerNovelty() {
        let n = notes("- Notch: una.\n- Sonido: dos.\n- Ventanas: tres.\n")
        XCTAssertEqual(n.highlights.count, 3)
    }
}

/// El recorrido de novedades. Lo que se prueba es que no se le vaya de las manos:
/// una versión con veintitrés puntos no puede ser veintitrés pantallas.
final class HighlightsTests: XCTestCase {
    private let sample = """
    # Cambios

    ## 0.5.0 — 2026-09-08

    **Nuevo**
    - Notch: funciona también en los Mac sin notch.
    - Rendimiento: CPU por núcleo, GPU y temperatura.
    - Sonido: ecualizador de 10 bandas.
    - Sonido: amplificación hasta el 400 %.
    - Sonido: prioridad de salidas.
    - Limpiador de apps: encuentra restos de apps que ya borraste.

    **Arreglado**
    - Notch: los menús iban a tirones.
    - Ajustes: doce traducciones corregidas.
    """

    func testFixesAreNotPartOfTheTour() {
        let notes = ReleaseNotes.all(from: sample).first!
        XCTAssertEqual(notes.items.count, 8)
        XCTAssertEqual(notes.newItems.count, 6)
        XCTAssertFalse(notes.highlights.contains { $0.detail.contains("tirones") })
    }

    /// Tres mejoras de sonido seguidas no pueden llevarse medio recorrido.
    func testOneScreenPerArea() {
        let highlights = ReleaseNotes.all(from: sample).first!.highlights
        XCTAssertEqual(highlights.count, 4)
        XCTAssertEqual(highlights.filter { $0.symbol.contains("slider") }.count, 1)
    }

    func testNeverMoreThanEightScreens() {
        let many = "## 1.0.0\n\n**Nuevo**\n" + (1...30).map { "- Cosa \($0): algo nuevo." }.joined(separator: "\n")
        XCTAssertLessThanOrEqual(ReleaseNotes.all(from: many).first!.highlights.count,
                                 ReleaseNotes.maxHighlights)
    }
}

/// Que «Novedades…» no se quede mudo.
///
/// La 0.5.1 solo traía arreglos, el recorrido los descarta a propósito y el menú no
/// hacía nada al pulsarlo: ninguna pantalla que enseñar, ninguna ventana, ningún
/// aviso. Al pedirlas a mano hay que enseñar lo que haya.
final class ReleaseNotesOnlyFixesTests: XCTestCase {
    private let soloArreglos = """
    # Cambios

    ## 0.5.1 — 2026-09-11

    **Arreglado**
    - Rendimiento: algunos nombres de apps salían con letras rotas.
    - Notch: el clic en la batería abría Ajustes del Sistema en General.
    """

    private var notes: ReleaseNotes {
        ReleaseNotes.notes(for: "0.5.1", in: soloArreglos)!
    }

    func testUnaVersionDeSoloArreglosNoTieneNovedades() {
        XCTAssertTrue(notes.newItems.isEmpty)
        XCTAssertTrue(notes.highlights.isEmpty)   // al actualizar no se pasea por los arreglos
        XCTAssertTrue(notes.isOnlyFixes)
    }

    func testPedidasAManoSeEnsenanLosArreglos() {
        XCTAssertEqual(notes.highlights(includingFixes: true).count, 2)
    }

    /// Y una versión con novedades no cambia: los arreglos van detrás, no en medio.
    func testConNovedadesLosArreglosVanDespues() {
        let mixto = """
        ## 0.6.0 — 2026-09-14

        **Nuevo**
        - Portapapeles: lista de apps que no se guardan.

        **Arreglado**
        - Notch: el clic en la batería abría la sección equivocada.
        """
        let n = ReleaseNotes.notes(for: "0.6.0", in: mixto)!
        XCTAssertFalse(n.isOnlyFixes)
        XCTAssertEqual(n.highlights.count, 1)
        XCTAssertEqual(n.highlights(includingFixes: true).count, 2)
        XCTAssertEqual(n.highlights(includingFixes: true).first, n.highlights.first)
    }

    /// El CHANGELOG de verdad, el que se empaqueta con la app: la versión de arriba
    /// del todo tiene que tener algo que enseñar al pulsar «Novedades…».
    func testElChangelogDelRepositorioEnsenaAlgo() throws {
        let raiz = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for archivo in ["CHANGELOG.md", "CHANGELOG.en.md"] {
            let url = raiz.appendingPathComponent(archivo)
            guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("No está \(archivo) junto a las fuentes")
            }
            let ultima = try XCTUnwrap(ReleaseNotes.all(from: markdown).first, archivo)
            XCTAssertFalse(ultima.highlights(includingFixes: true).isEmpty,
                           "\(archivo): la versión \(ultima.version) no enseñaría nada")
        }
    }
}
