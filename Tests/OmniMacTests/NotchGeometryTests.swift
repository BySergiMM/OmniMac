import XCTest
import AppKit
@testable import OmniMac

/// La geometría del notch en Macs de verdad. Cada caso son las medidas en puntos de
/// una pantalla concreta, para comprobar que la app se adapta sola sin listas de
/// modelos: MacBook con notch, MacBook sin notch, iMac y monitores externos.
final class NotchGeometryTests: XCTestCase {

    /// MacBook Pro de 14" a resolución por defecto: notch de 196 pt de ancho.
    private func macBookPro14() -> NotchGeometry {
        NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                      safeAreaTop: 32,
                      auxiliaryWidths: (left: 658, right: 658),
                      menuBarHeight: 38)
    }

    /// iMac de 24": sin notch, barra de menús normal.
    private func imac24() -> NotchGeometry {
        NotchGeometry(frame: CGRect(x: 0, y: 0, width: 2048, height: 1152),
                      safeAreaTop: 0,
                      auxiliaryWidths: nil,
                      menuBarHeight: 24)
    }

    func testMacBookProUsesTheRealNotchWidth() {
        let g = macBookPro14()
        XCTAssertTrue(g.hasNotch)
        XCTAssertEqual(g.notchSize.width, 196)
        XCTAssertEqual(g.notchSize.height, 32)
    }

    func testNotchScreenWithoutAuxiliaryAreasFallsBack() {
        // Algunas configuraciones no publican las dos mitades de la barra de menús.
        let g = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                              safeAreaTop: 32,
                              auxiliaryWidths: nil,
                              menuBarHeight: 38)
        XCTAssertEqual(g.notchSize.width, NotchGeometry.fallbackNotchWidth)
    }

    func testScreenWithoutNotchDrawsAnIslandSizedToTheScreen() {
        let g = imac24()
        XCTAssertFalse(g.hasNotch)
        // Proporcional al ancho, pero acotada para no quedar ridícula.
        XCTAssertTrue(NotchGeometry.islandWidthRange.contains(g.notchSize.width))
        XCTAssertEqual(g.notchSize.height, 30, "la isla cuelga un poco de la barra")
    }

    func testSmallScreenGetsTheMinimumIslandInsteadOfAProportion() {
        let g = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                              safeAreaTop: 0, auxiliaryWidths: nil, menuBarHeight: 24)
        XCTAssertEqual(g.notchSize.width, NotchGeometry.islandWidthRange.lowerBound)
    }

    func testUltrawideDoesNotGetAGiantIsland() {
        let g = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                              safeAreaTop: 0, auxiliaryWidths: nil, menuBarHeight: 24)
        XCTAssertEqual(g.notchSize.width, NotchGeometry.islandWidthRange.upperBound)
    }

    func testCollapsedFrameIsCentredAndFlushWithTheTop() {
        for g in [macBookPro14(), imac24()] {
            XCTAssertEqual(g.collapsedFrame.midX, g.screenFrame.midX, accuracy: 0.001)
            XCTAssertEqual(g.collapsedFrame.maxY, g.screenFrame.maxY, accuracy: 0.001)
        }
    }

    func testHoverZoneCoversTheTopCentreOfTheScreen() {
        for g in [macBookPro14(), imac24()] {
            let topCentre = CGPoint(x: g.screenFrame.midX, y: g.screenFrame.maxY - 1)
            XCTAssertTrue(g.hoverZone.contains(topCentre))
        }
    }

    func testExpandedPanelNeverOverflowsTheScreen() {
        // Un monitor pequeño (o una resolución muy escalada) no debe sacar el panel
        // por los bordes: se recorta al ancho de la pantalla menos el margen.
        let g = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                              safeAreaTop: 0, auxiliaryWidths: nil, menuBarHeight: 24)
        XCTAssertLessThanOrEqual(g.expandedSize.width, 600 - NotchGeometry.screenMargin)
        XCTAssertGreaterThanOrEqual(g.expandedSize.width, g.notchSize.width)
    }

    func testExpandedPanelLeavesRoomOnBothSidesOfTheNotch() {
        // Las cinco pestañas de la izquierda y el grupo de la derecha tienen que caber.
        let g = macBookPro14()
        let free = g.expandedSize.width - g.notchSize.width
        XCTAssertGreaterThanOrEqual(free / 2, NotchModel.sideClearance - 0.001)
    }

    func testBodySitsAgainstTheTopAndInsideTheWindow() {
        let g = macBookPro14()
        XCTAssertEqual(g.bodyFrame.maxY, g.screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(g.expandedFrame.maxY, g.screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(g.expandedFrame.width, g.expandedSize.width + g.shadowMargin * 2, accuracy: 0.001)
    }

    func testSecondaryScreenIsPlacedOnItsOwnFrameNotOnTheOrigin() {
        // Un monitor a la derecha del principal: el notch va centrado en ÉL.
        let g = NotchGeometry(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                              safeAreaTop: 0, auxiliaryWidths: nil, menuBarHeight: 24)
        XCTAssertEqual(g.collapsedFrame.midX, 1512 + 960, accuracy: 0.001)
    }
}
