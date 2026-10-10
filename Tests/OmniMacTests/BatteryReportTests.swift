import IOKit.ps
import XCTest
@testable import OmniMac

/// La batería: lo que se lee de IOKit, cómo se cuenta y el historial de salud.
final class BatteryReportTests: XCTestCase {
    private func source(percent: Int, charging: Bool, plugged: Bool, charged: Bool = false,
                        toFull: Int = -1, toEmpty: Int = -1) -> [String: Any] {
        [kIOPSCurrentCapacityKey: percent, kIOPSMaxCapacityKey: 100,
         kIOPSIsChargingKey: charging, kIOPSIsChargedKey: charged,
         kIOPSPowerSourceStateKey: plugged ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
         kIOPSTimeToFullChargeKey: toFull, kIOPSTimeToEmptyKey: toEmpty]
    }

    func testMinusOneMeansStillCalculating() {
        let report = BatteryReport(powerSource: source(percent: 57, charging: true, plugged: true))
        XCTAssertEqual(report.percent, 57)
        XCTAssertNil(report.minutesToFull)
        XCTAssertEqual(report.status, .charging(minutesToFull: nil))
    }

    func testStatuses() {
        XCTAssertEqual(BatteryReport(powerSource: source(percent: 57, charging: true, plugged: true, toFull: 170)).status,
                       .charging(minutesToFull: 170))
        // El límite de carga de macOS: enchufado, al 80 % y sin cargar.
        XCTAssertEqual(BatteryReport(powerSource: source(percent: 80, charging: false, plugged: true)).status,
                       .pluggedNotCharging)
        XCTAssertEqual(BatteryReport(powerSource: source(percent: 100, charging: false, plugged: true, charged: true)).status,
                       .full)
        XCTAssertEqual(BatteryReport(powerSource: source(percent: 40, charging: false, plugged: false, toEmpty: 125)).status,
                       .onBattery(minutesToEmpty: 125))
    }

    func testDurations() {
        XCTAssertEqual(BatteryReport.duration(45), "45 min")
        XCTAssertEqual(BatteryReport.duration(120), "2 h")
        XCTAssertEqual(BatteryReport.duration(170), "2 h 50 min")
    }

    /// Lo que da un M5 con macOS 27: las cifras en mAh van dentro de `BatteryData`.
    func testRegistryOnAppleSilicon() {
        var report = BatteryReport()
        report.apply(registry: [
            "CycleCount": 25, "DesignCycleCount9C": 1000, "MaxCapacity": 100,
            "BatteryData": ["FullChargeCapacity": 6048, "NominalChargeCapacity": 6200, "DesignCapacity": 6249],
        ])
        XCTAssertEqual(report.cycleCount, 25)
        XCTAssertEqual(report.designCycleCount, 1000)
        XCTAssertEqual(report.designCapacity, 6249)
        XCTAssertEqual(report.currentCapacity, 6200)
        XCTAssertEqual(report.capacityRatio ?? 0, 99.2, accuracy: 0.1)
    }

    /// En los Intel las cifras van sueltas y la actual se llama «AppleRawMaxCapacity».
    func testRegistryOnIntel() {
        var report = BatteryReport()
        report.apply(registry: ["CycleCount": 312, "DesignCapacity": 5103, "AppleRawMaxCapacity": 4300])
        XCTAssertEqual(report.designCapacity, 5103)
        XCTAssertEqual(report.currentCapacity, 4300)
        XCTAssertNil(report.designCycleCount)
    }

    func testChargerPeek() {
        var report = BatteryReport(powerSource: source(percent: 57, charging: true, plugged: true))
        report.adapterWatts = 30
        XCTAssertEqual(report.chargerPeek.subtitle, "30 W · 57 %")
        report.minutesToFull = 95
        XCTAssertEqual(report.chargerPeek.subtitle, "30 W · 57 % · " + L("llena en 1 h 35 min", "full in 1 h 35 min"))
        // Sin vatios (cargador sin negociar) sale solo la carga.
        var plain = BatteryReport(powerSource: source(percent: 80, charging: false, plugged: true))
        plain.adapterWatts = nil
        XCTAssertEqual(plain.chargerPeek.subtitle, "80 %")
    }

    /// La salida real de `system_profiler -json SPPowerDataType`, con su espacio duro.
    func testMacHealthFromSystemProfiler() throws {
        let json = """
        {"SPPowerDataType":[{"_name":"spbattery_information",
          "sppower_battery_health_info":{"sppower_battery_cycle_count":25,
            "sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"100\u{00a0}%"}},
          {"_name":"sppower_ac_charger_information"}]}
        """
        let info = try XCTUnwrap(MacHealth.parse(Data(json.utf8)))
        XCTAssertEqual(info.maximumCapacity, 100)
        XCTAssertEqual(info.condition, "Good")
        XCTAssertNil(MacHealth.parse(Data("{\"SPPowerDataType\":[{}]}".utf8)))   // un Mac sin batería
    }
}

final class BatteryHistoryTests: XCTestCase {
    func testOneReadingPerDay() {
        var history = BatteryHistory()
        XCTAssertTrue(history.record(day: "2026-10-06", capacity: 6200, cycles: 25))
        XCTAssertFalse(history.record(day: "2026-10-06", capacity: 6190, cycles: 25))
        XCTAssertTrue(history.record(day: "2026-10-07", capacity: 6195, cycles: 26))
        XCTAssertEqual(history.entries.map(\.capacity), [6200, 6195])
    }

    func testNoTrendWithASingleDay() {
        var history = BatteryHistory()
        history.record(day: "2026-10-06", capacity: 6200, cycles: 25)
        XCTAssertNil(history.trend)
        XCTAssertFalse(history.record(day: "2026-10-07", capacity: 0, cycles: nil))   // lectura vacía
    }

    func testTrendFromFirstToLast() throws {
        var history = BatteryHistory()
        history.record(day: "2026-10-06", capacity: 6200, cycles: 25)
        history.record(day: "2026-11-06", capacity: 6150, cycles: 40)
        history.record(day: "2027-01-06", capacity: 6076, cycles: 70)
        let trend = try XCTUnwrap(history.trend)
        XCTAssertEqual(trend.change, -2.0, accuracy: 0.01)
        XCTAssertEqual(trend.summary(languageCode: "es"), "Desde el 6 oct 2026: 6200 → 6076 mAh (−2,0 %) · 25 → 70 ciclos")
        XCTAssertEqual(trend.summary(languageCode: "en"), "Since Oct 6, 2026: 6200 → 6076 mAh (−2.0%) · 25 → 70 cycles")
    }

    func testKeepsAtMostTwoYears() {
        var history = BatteryHistory()
        for day in 0..<(BatteryHistory.limit + 10) {
            history.record(day: "d\(day)", capacity: 6000, cycles: nil)
        }
        XCTAssertEqual(history.entries.count, BatteryHistory.limit)
        XCTAssertEqual(history.entries.first?.day, "d10")
    }

    func testSurvivesASaveAndLoad() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BatteryHistoryTests"))
        defaults.removePersistentDomain(forName: "BatteryHistoryTests")
        defer { defaults.removePersistentDomain(forName: "BatteryHistoryTests") }
        var history = BatteryHistory()
        history.record(day: "2026-10-06", capacity: 6200, cycles: 25)
        history.record(day: "2026-10-07", capacity: 6199, cycles: nil)
        history.save(defaults)
        XCTAssertEqual(BatteryHistory.load(defaults), history)
    }
}

/// Los avisos nuevos de batería: desenchufar y calor cargando.
final class BatteryAlertTests: XCTestCase {
    private func engine(unplug: Bool = true) -> AlertEngine {
        var settings = AlertSettings()
        settings.unplugEnabled = unplug
        settings.unplugPercent = 80
        return AlertEngine(settings: settings)
    }

    func testUnplugFiresOnReachingTheLevel() {
        var engine = engine()
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 79, charging: true)).isEmpty)
        XCTAssertEqual(engine.evaluate(.init(batteryPercent: 80, charging: true)).map(\.id), ["unplug"])
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 81, charging: true)).isEmpty)   // una sola vez
    }

    func testUnplugRearmsOnTheNextCharge() {
        var engine = engine()
        _ = engine.evaluate(.init(batteryPercent: 80, charging: true))
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 79, charging: false)).isEmpty)
        XCTAssertEqual(engine.evaluate(.init(batteryPercent: 82, charging: true)).map(\.id), ["unplug"])
    }

    /// El límite de macOS la deja al 80 % enchufada durante horas: un aviso, no uno por minuto.
    func testUnplugDoesNotNagWhileItStaysPlugged() {
        var engine = engine()
        _ = engine.evaluate(.init(batteryPercent: 80, charging: true))
        for _ in 0..<120 {
            XCTAssertTrue(engine.evaluate(.init(batteryPercent: 80, charging: true)).isEmpty)
        }
    }

    func testUnplugIsOffByDefault() {
        var engine = AlertEngine()
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 95, charging: true)).isEmpty)
    }

    func testHeatNeedsTwoReadingsAndTheCharger() {
        var engine = engine(unplug: false)
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 50, charging: false, batteryTemperature: 45)).isEmpty)
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 50, charging: true, batteryTemperature: 42)).isEmpty)
        XCTAssertEqual(engine.evaluate(.init(batteryPercent: 50, charging: true, batteryTemperature: 42)).map(\.id),
                       ["batteryHeat"])
        // Sin lectura (vuelta sin sensores) no se rompe nada ni se repite.
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 50, charging: true)).isEmpty)
        XCTAssertTrue(engine.evaluate(.init(batteryPercent: 50, charging: true, batteryTemperature: 41)).isEmpty)
    }
}
