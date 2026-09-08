import XCTest
@testable import OmniMac

/// Los avisos. Lo que se prueba aquí es que **no sean pesados**: un umbral pelado
/// da veinte notificaciones cuando el valor baila alrededor de la línea.
final class AlertStateTests: XCTestCase {
    func testNeedsToSustainBeforeFiring() {
        var state = AlertState()
        let rule = AlertRule(threshold: 80, sustain: 3, hysteresis: 10)
        XCTAssertFalse(state.update(90, rule: rule))
        XCTAssertFalse(state.update(90, rule: rule))
        XCTAssertTrue(state.update(90, rule: rule))     // la tercera seguida
    }

    func testAPeakDoesNotFire() {
        var state = AlertState()
        let rule = AlertRule(threshold: 80, sustain: 3, hysteresis: 10)
        XCTAssertFalse(state.update(95, rule: rule))
        XCTAssertFalse(state.update(10, rule: rule))    // se corta la racha
        XCTAssertFalse(state.update(95, rule: rule))
        XCTAssertFalse(state.update(95, rule: rule))
    }

    func testDoesNotRepeatWhileItStaysBad() {
        var state = AlertState()
        let rule = AlertRule(threshold: 80, sustain: 1, hysteresis: 10)
        XCTAssertTrue(state.update(90, rule: rule))
        for _ in 0..<20 { XCTAssertFalse(state.update(90, rule: rule)) }
    }

    /// Rozar la línea no rearma: hay que bajar del umbral menos el margen.
    func testRearmsOnlyWhenClearlyBetter() {
        var state = AlertState()
        let rule = AlertRule(threshold: 80, sustain: 1, hysteresis: 10)
        XCTAssertTrue(state.update(90, rule: rule))
        XCTAssertFalse(state.update(75, rule: rule))    // dentro del margen: no rearma
        XCTAssertFalse(state.update(85, rule: rule))    // y por eso no vuelve a avisar
        XCTAssertFalse(state.update(60, rule: rule))    // ahora sí rearma
        XCTAssertTrue(state.update(90, rule: rule))
    }

    func testBelowRulesWorkTheOtherWayRound() {
        var state = AlertState()
        let rule = AlertRule(threshold: 10, sustain: 1, hysteresis: 2, below: true)
        XCTAssertTrue(state.update(8, rule: rule))      // 8 GB < 10
        XCTAssertFalse(state.update(9, rule: rule))
        XCTAssertFalse(state.update(20, rule: rule))    // rearma
        XCTAssertTrue(state.update(5, rule: rule))
    }
}

final class AlertEngineTests: XCTestCase {
    func testDiskFiresOnTheFirstSample() {
        var engine = AlertEngine()
        let alerts = engine.evaluate(.init(diskFreeGB: 4))
        XCTAssertEqual(alerts.map(\.id), ["disk"])
    }

    /// Con el cargador puesto, la batería baja no es noticia.
    func testNoBatteryAlertWhileCharging() {
        var engine = AlertEngine()
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 5, charging: true)).isEmpty)
        XCTAssertEqual(engine.evaluate(.init(batteryPercent: 5, charging: false)).map(\.id), ["battery"])
    }

    func testDisabledRulesSayNothing() {
        var settings = AlertSettings()
        settings.diskEnabled = false
        var engine = AlertEngine(settings: settings)
        XCTAssertTrue(engine.evaluate(.init(diskFreeGB: 1)).isEmpty)
    }

    func testMissingDataIsNotAnAlert() {
        var engine = AlertEngine()
        XCTAssertTrue(engine.evaluate(.init()).isEmpty)
    }

    /// Varias cosas mal a la vez salen juntas, cada una una sola vez.
    func testSeveralAtOnce() {
        var engine = AlertEngine()
        let first = engine.evaluate(.init(memoryPressure: 2, diskFreeGB: 3, thermal: 3))
        XCTAssertEqual(Set(first.map(\.id)), ["disk"])   // memoria y calor necesitan aguante
        for _ in 0..<5 { _ = engine.evaluate(.init(memoryPressure: 2, thermal: 3)) }
        XCTAssertTrue(engine.evaluate(.init(diskFreeGB: 3)).isEmpty)   // el disco ya avisó
    }
}
