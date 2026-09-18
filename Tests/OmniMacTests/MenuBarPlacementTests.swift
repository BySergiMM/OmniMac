import XCTest
@testable import OmniMac

/// Dónde se colocan los iconos de OmniMac respecto a la línea del escondedor.
///
/// A más número, más a la izquierda. macOS reescribe estas posiciones por su cuenta
/// cada vez que aparece un icono nuevo, y con eso uno de los nuestros se colaba entre
/// la línea y la flecha: allí lo que sueltes no se esconde y parece que la función
/// está rota. Los números de las pruebas son los que tenía Sergi de verdad.
final class MenuBarPlacementTests: XCTestCase {
    private let flecha = "com.seergiii.omnimac.menubar.separator"
    private let app = "com.seergiii.omnimac.main"
    private let grafica = "com.seergiii.omnimac.stats"

    private var orden: [String] { [flecha, app, grafica] }

    /// macOS 27 descarta un icono que llegue a la mitad de la pantalla: el expansor se
    /// queda por debajo, medido en la pantalla más estrecha; antes, cualquier ancho valía.
    func testEnMacOS27ElExpansorNoLlegaAMediaPantalla() {
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512, 2560], macOS27: true), 680)
        XCTAssertLessThan(MenuBarFeature.pushWidth(screenWidths: [1512, 2560], macOS27: true), 1512 / 2)
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [], macOS27: true), 648)
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: false), 10_000)
    }

    /// En un portátil con notch, el expansor no puede crecer más allá del filo del
    /// notch: si su borde derecho está a 416 pt del filo, se topa ahí (más un pelín
    /// para meter el último icono bajo el notch), no en el 45 % de la pantalla.
    func testConNotchElExpansorNoCruzaAlOtroLado() {
        // 416 + 12 de margen = 428, por debajo del 45 % (680): manda el notch.
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: true,
                                                notchRightEdgeGap: 416), 428)
        XCTAssertLessThan(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: true,
                                                   notchRightEdgeGap: 416), 680)
        // Si el hueco es enorme (pocos iconos a la derecha), el 45 % sigue mandando.
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: true,
                                                notchRightEdgeGap: 5_000), 680)
        // Nunca baja del mínimo aunque el hueco sea minúsculo (o dejaría de esconder).
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: true,
                                                notchRightEdgeGap: 50), 200)
        // Sin notch en juego, el tope es el de siempre.
        XCTAssertEqual(MenuBarFeature.pushWidth(screenWidths: [1512], macOS27: true,
                                                notchRightEdgeGap: nil), 680)
    }

    /// Todo en su sitio: no se toca nada.
    func testLoQueYaEstaBienNoSeMueve() {
        let ahora = [flecha: 261.0, app: 243.0, grafica: 225.0]
        let mover = MenuBarFeature.placements(for: orden, current: ahora, limit: 301, force: false)
        XCTAssertTrue(mover.isEmpty)
    }

    /// El caso real: la gráfica se coló entre la línea (301) y la flecha (261).
    func testElQueSeCuelaVuelveALaFila() {
        let ahora = [flecha: 261.0, app: 243.0, grafica: 287.0]
        let mover = MenuBarFeature.placements(for: orden, current: ahora, limit: 301, force: false)
        XCTAssertEqual(mover, [grafica: 225])
        XCTAssertLessThan(mover[grafica]!, ahora[app]!)   // a la derecha del icono de la app
    }

    /// Un icono nuestro a la izquierda de la línea es el caso grave: el escondedor se
    /// tragaba la propia flecha para recuperarlos.
    func testALaIzquierdaDeLaLineaSeRescata() {
        let ahora = [flecha: 320.0, app: 243.0, grafica: 225.0]
        let mover = MenuBarFeature.placements(for: orden, current: ahora, limit: 301, force: false)
        XCTAssertEqual(mover[flecha], 283)
        XCTAssertLessThan(mover[flecha]!, 301)
    }

    /// «Recolocar» los pone todos en fila, respetando el orden.
    func testRecolocarLosOrdenaTodos() {
        let ahora = [flecha: 100.0, app: 243.0, grafica: 287.0]
        let mover = MenuBarFeature.placements(for: orden, current: ahora, limit: 301, force: true)
        XCTAssertEqual(mover, [flecha: 283, app: 265, grafica: 247])
    }

    /// La línea nunca sale en el reparto: es el límite que pone la persona, y moverla
    /// destaparía de golpe lo que tuviera escondido.
    func testLaLineaNoSeReparteNunca() {
        let linea = "com.seergiii.omnimac.menubar.expander"
        XCTAssertFalse(MenuBarFeature.ownIconNames.contains(linea))
        let mover = MenuBarFeature.placements(for: MenuBarFeature.ownIconNames,
                                              current: [:], limit: 301, force: true)
        XCTAssertNil(mover[linea])
        XCTAssertEqual(mover.count, MenuBarFeature.ownIconNames.count)   // sin posición previa, todos
    }

    /// Los iconos de módulo van detrás de los tres fijos, nunca delante.
    func testLosIconosDeModuloVanDetras() {
        let mover = MenuBarFeature.placements(for: MenuBarFeature.ownIconNames,
                                              current: [:], limit: 301, force: true)
        let modulos = MenuBarFeature.ownIconNames.filter { $0.hasPrefix("omnimac.module.") }
        for modulo in modulos {
            XCTAssertLessThan(mover[modulo]!, mover[flecha]!)
        }
    }
}

/// El destrozo de verdad: arrastrando la línea, la flecha acabó a su izquierda.
///
/// Con la flecha (432) más a la izquierda que la línea (296), el escondedor se traga
/// su propio botón de rescate: los iconos se van y no hay dónde pulsar para que
/// vuelvan. Son las posiciones que tenía Sergi el 14 de septiembre de 2026.
final class MenuBarRescueTests: XCTestCase {
    private let linea = 296.0
    private let flecha = "com.seergiii.omnimac.menubar.separator"
    private let app = "com.seergiii.omnimac.main"
    private let grafica = "com.seergiii.omnimac.stats"

    private var roto: [String: Double] {
        [flecha: 432, app: 358, grafica: 287,
         "omnimac.module.keepawake": 322, "omnimac.module.clipboard": 220,
         "omnimac.module.tools": 223, "omnimac.module.sound": 184,
         "omnimac.module.snapping": 166]
    }

    func testTodosLosNuestrosAcabanALaDerechaDeLaLinea() {
        let mover = MenuBarFeature.placements(for: MenuBarFeature.ownIconNames,
                                              current: roto, limit: linea, force: false)
        for name in MenuBarFeature.ownIconNames {
            let final = mover[name] ?? roto[name]!
            XCTAssertLessThan(final, linea, "\(name) sigue a la izquierda de la línea")
        }
    }

    /// Y la flecha, la primera de todas: es la que rescata a las demás.
    func testLaFlechaVuelveLaPrimera() {
        let mover = MenuBarFeature.placements(for: MenuBarFeature.ownIconNames,
                                              current: roto, limit: linea, force: false)
        let posicion = { (name: String) in mover[name] ?? self.roto[name]! }
        XCTAssertEqual(posicion(flecha), 278)
        XCTAssertGreaterThan(posicion(flecha), posicion(app))
        XCTAssertGreaterThan(posicion(app), posicion(grafica))
    }

    /// El orden queda sin empates: dos iconos en el mismo sitio los vuelve a barajar
    /// macOS, y volveríamos a empezar.
    func testNingunEmpate() {
        let mover = MenuBarFeature.placements(for: MenuBarFeature.ownIconNames,
                                              current: roto, limit: linea, force: false)
        let finales = MenuBarFeature.ownIconNames.map { mover[$0] ?? roto[$0]! }
        XCTAssertEqual(Set(finales).count, finales.count)
        XCTAssertEqual(finales, finales.sorted(by: >))   // de izquierda a derecha, en orden
    }
}

/// Cuándo hay que rehacer los iconos en caliente.
///
/// Rehacerlos quita y vuelve a poner los NSStatusItem, y **quitar uno borra su
/// posición guardada** (comprobado: AppKit se la lleva por delante). Así que solo se
/// hace cuando de verdad hace falta: cuando el escondedor se está tragando algo
/// nuestro y no queda dónde pulsar para recuperarlo.
final class MenuBarSwallowedTests: XCTestCase {
    private let flecha = "com.seergiii.omnimac.menubar.separator"
    private let app = "com.seergiii.omnimac.main"
    private var orden: [String] { [flecha, app] }

    func testTodoADerechaDeLaLineaNoSeToca() {
        XCTAssertFalse(MenuBarFeature.swallowed(positions: [flecha: 278, app: 260],
                                                names: orden, limit: 296))
    }

    /// El caso que rompe la barra: la flecha, a la izquierda de la línea.
    func testLaFlechaTragadaPideRescate() {
        XCTAssertTrue(MenuBarFeature.swallowed(positions: [flecha: 432, app: 260],
                                               names: orden, limit: 296))
    }

    /// Justo encima de la línea también cuenta: ahí ya no se ve.
    func testEnLaMismaLineaTambien() {
        XCTAssertTrue(MenuBarFeature.swallowed(positions: [flecha: 296, app: 260],
                                               names: orden, limit: 296))
    }

    /// Sin posición guardada (AppKit acaba de borrarla) hay que recolocar.
    func testSinPosicionSeRecoloca() {
        XCTAssertTrue(MenuBarFeature.swallowed(positions: [app: 260], names: orden, limit: 296))
    }

    /// Y estar desordenado, a secas, no justifica rehacerlos: eso se arregla al
    /// arrancar, y rehacerlos en caliente parpadea.
    func testDesordenadoPeroVisibleNoPideRescate() {
        XCTAssertFalse(MenuBarFeature.swallowed(positions: [flecha: 240, app: 260],
                                                names: orden, limit: 296))
    }
}
