import XCTest
@testable import OmniMac

/// El ratón quieto no elige ventana en el selector ⌘Tab; en cuanto se mueve, sí.
final class SwitcherHoverGateTests: XCTestCase {
    func testStillMouseUnderThePanelIsIgnored() {
        var gate = SwitcherHoverGate()
        gate.reset(at: CGPoint(x: 500, y: 400))
        XCTAssertFalse(gate.shouldFollow(mouseAt: CGPoint(x: 500, y: 400)))
        XCTAssertFalse(gate.shouldFollow(mouseAt: CGPoint(x: 500, y: 400)))
    }

    func testTheSmallestMovementCounts() {
        var gate = SwitcherHoverGate()
        gate.reset(at: CGPoint(x: 500, y: 400))
        XCTAssertTrue(gate.shouldFollow(mouseAt: CGPoint(x: 500.5, y: 400)))
    }

    func testAfterMovingAStillMouseIsIgnoredAgain() {
        // La cuadrícula puede desplazarse con el teclado bajo un ratón quieto.
        var gate = SwitcherHoverGate()
        gate.reset(at: CGPoint(x: 500, y: 400))
        XCTAssertTrue(gate.shouldFollow(mouseAt: CGPoint(x: 520, y: 400)))
        XCTAssertFalse(gate.shouldFollow(mouseAt: CGPoint(x: 520, y: 400)))
        XCTAssertTrue(gate.shouldFollow(mouseAt: CGPoint(x: 521, y: 401)))
    }

    func testEachOpeningStartsStill() {
        var gate = SwitcherHoverGate()
        gate.reset(at: CGPoint(x: 10, y: 10))
        XCTAssertTrue(gate.shouldFollow(mouseAt: CGPoint(x: 300, y: 300)))
        gate.reset(at: CGPoint(x: 300, y: 300))
        XCTAssertFalse(gate.shouldFollow(mouseAt: CGPoint(x: 300, y: 300)))
    }

    // Panel de 600×300 con la esquina inferior izquierda en (100, 200) de la pantalla.
    private let panel = CGRect(x: 100, y: 200, width: 600, height: 300)
    private let cells: [Int: CGRect] = [
        0: CGRect(x: 16, y: 34, width: 210, height: 168),
        1: CGRect(x: 234, y: 34, width: 210, height: 168),
    ]

    func testFindsTheCellUnderTheMouse() {
        // La pantalla cuenta desde abajo y SwiftUI desde arriba: y = 400 queda a 100 del borde de arriba.
        XCTAssertEqual(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 400), panelFrame: panel, cellFrames: cells), 0)
        XCTAssertEqual(SwitcherHoverGate.cell(at: CGPoint(x: 400, y: 400), panelFrame: panel, cellFrames: cells), 1)
    }

    func testTheGapBetweenCellsAndTheHeaderChooseNothing() {
        XCTAssertNil(SwitcherHoverGate.cell(at: CGPoint(x: 330, y: 400), panelFrame: panel, cellFrames: cells))
        XCTAssertNil(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 490), panelFrame: panel, cellFrames: cells))
        XCTAssertNil(SwitcherHoverGate.cell(at: CGPoint(x: 50, y: 400), panelFrame: panel, cellFrames: cells))
    }

    func testCellsScrolledOutOfSightDoNotCount() {
        // Una celda que sube bajo la cabecera y otra que asoma por debajo del panel.
        let scrolled: [Int: CGRect] = [
            0: CGRect(x: 16, y: -100, width: 210, height: 168),
            1: CGRect(x: 16, y: 250, width: 210, height: 168),
        ]
        // Sobre la cabecera (a 20 del borde de arriba): nada.
        XCTAssertNil(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 480), panelFrame: panel, gridTop: 30, cellFrames: scrolled))
        // Debajo del panel, donde seguiría la celda 1: nada.
        XCTAssertNil(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 150), panelFrame: panel, gridTop: 30, cellFrames: scrolled))
        // La parte que sí se ve de cada una.
        XCTAssertEqual(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 450), panelFrame: panel, gridTop: 30, cellFrames: scrolled), 0)
        XCTAssertEqual(SwitcherHoverGate.cell(at: CGPoint(x: 200, y: 220), panelFrame: panel, gridTop: 30, cellFrames: scrolled), 1)
    }

}

/// Qué ventana sale elegida al abrir ⌘Tab.
final class SwitcherInitialSelectionTests: XCTestCase {
    func testNormallyThePreviousWindow() {
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 5, backward: false, fromOwnWindow: false), 1)
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 5, backward: true, fromOwnWindow: false), 4)
    }

    /// Desde Ajustes o las Novedades, la primera de la lista es la última que usabas.
    func testFromAnOmniMacWindowGoesBackToTheLastOne() {
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 5, backward: false, fromOwnWindow: true), 0)
        // ⇧⌘Tab sigue yendo a la última de la lista.
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 5, backward: true, fromOwnWindow: true), 4)
    }

    func testOneOrNoWindows() {
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 1, backward: false, fromOwnWindow: false), 0)
        XCTAssertEqual(WindowSwitcherFeature.initialSelection(count: 0, backward: true, fromOwnWindow: true), 0)
    }
}
