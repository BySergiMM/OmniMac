import XCTest
@testable import OmniMac

/// La decisión más cara del módulo: parar la sesión con la tapa cerrada duerme el Mac
/// en el acto. Por eso vive aparte de la vista y se prueba entera.
final class KeepAwakeBatteryRuleTests: XCTestCase {
    private typealias Rule = KeepAwakeBatteryRule

    private func decide(level: Int, plugged: Bool = false, hasBattery: Bool = true,
                        enabled: Bool = true, threshold: Int = 20,
                        warned: Bool = false) -> Rule.Decision {
        Rule.decide(level: level, hasBattery: hasBattery, isPluggedIn: plugged,
                    enabled: enabled, threshold: threshold, alreadyWarned: warned)
    }

    // MARK: - Cuándo se corta

    func testStopsAtTheThreshold() {
        XCTAssertEqual(decide(level: 20), .stop(level: 20))
        XCTAssertEqual(decide(level: 19), .stop(level: 19))
        XCTAssertEqual(decide(level: 1), .stop(level: 1))
    }

    func testDoesNothingWellAboveTheThreshold() {
        XCTAssertEqual(decide(level: 80), .nothing)
        XCTAssertEqual(decide(level: 31), .nothing)
    }

    // MARK: - El aviso previo

    func testWarnsBeforeCutting() {
        // Con la tapa abierta da tiempo a enchufar; después del corte ya es tarde,
        // porque con la tapa cerrada el Mac se duerme en ese mismo momento.
        XCTAssertEqual(decide(level: 30), .warn(level: 30))
        XCTAssertEqual(decide(level: 21), .warn(level: 21))
    }

    func testWarnsOnlyOncePerSession() {
        XCTAssertEqual(decide(level: 25, warned: true), .nothing)
        // Pero el corte sigue llegando aunque ya se hubiera avisado.
        XCTAssertEqual(decide(level: 20, warned: true), .stop(level: 20))
    }

    // MARK: - Cuándo no hay nada que proteger

    func testDoesNothingWithTheCharger() {
        XCTAssertEqual(decide(level: 5, plugged: true), .nothing)
    }

    func testDoesNothingWithoutABattery() {
        // Un Mac de sobremesa no tiene de qué preocuparse.
        XCTAssertEqual(decide(level: 0, hasBattery: false), .nothing)
    }

    func testDoesNothingIfTheProtectionIsOff() {
        XCTAssertEqual(decide(level: 3, enabled: false), .nothing)
    }

    func testIgnoresTheEmptyReadingAtLaunch() {
        // IOKit devuelve 0 durante un instante al arrancar. Sin esta guarda, la
        // sesión se cortaba sola nada más empezar.
        XCTAssertEqual(decide(level: 0), .nothing)
    }

    func testRespectsACustomThreshold() {
        XCTAssertEqual(decide(level: 10, threshold: 10), .stop(level: 10))
        XCTAssertEqual(decide(level: 11, threshold: 10), .warn(level: 11))
        XCTAssertEqual(decide(level: 21, threshold: 10), .nothing)
    }
}

final class KeepAwakeEndingTests: XCTestCase {

    func testManualEndingIsNotWorthTelling() {
        // Si lo apagó el usuario, no hay nada que explicarle.
        let manual = KeepAwakeEnding(reason: .manual, batteryLevel: nil, at: Date())
        XCTAssertFalse(manual.worthTelling)
        XCTAssertTrue(manual.explanation.isEmpty)
    }

    func testEveryAutomaticEndingExplainsItself() {
        for reason in [KeepAwakeEndReason.timer, .lowBattery, .appQuit, .moduleOff, .trigger] {
            let ending = KeepAwakeEnding(reason: reason, batteryLevel: 17, at: Date())
            XCTAssertTrue(ending.worthTelling, "\(reason) debería contarse")
            XCTAssertFalse(ending.explanation.isEmpty, "\(reason) se quedó sin explicación")
        }
    }

    func testTheBatteryEndingSaysTheLevelAndWarnsAboutTheLid() {
        let ending = KeepAwakeEnding(reason: .lowBattery, batteryLevel: 17, at: Date())
        XCTAssertTrue(ending.explanation.contains("17"))
        XCTAssertTrue(ending.explanation.lowercased().contains("tapa")
                      || ending.explanation.lowercased().contains("lid"))
    }

    func testSurvivesADiskRoundTrip() {
        // Tiene que sobrevivir a que el Mac se duerma y la app se cierre: es su
        // único motivo de existir.
        let ending = KeepAwakeEnding(reason: .lowBattery, batteryLevel: 12, at: Date())
        let data = try! JSONEncoder().encode(ending)
        let back = try! JSONDecoder().decode(KeepAwakeEnding.self, from: data)
        XCTAssertEqual(back, ending)
    }
}
