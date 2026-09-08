import XCTest
@testable import OmniMac

/// Las cuentas del monitor de rendimiento, sin tocar el hardware.
///
/// Todo lo que sale de contadores acumulados se rompe igual: restas que se dan la
/// vuelta, muestras sin tiempo entre medias y unidades que no son las que parecen.
/// Estas pruebas están escritas contra esos tres fallos.
final class CPUTicksTests: XCTestCase {
    func testUsageBetweenTwoSamples() {
        let before = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let after = CPUTicks(user: 150, system: 75, idle: 1075, nice: 0)
        // 75 ocupados de 300 totales
        XCTAssertEqual(after.usage(since: before)!, 25, accuracy: 0.001)
    }

    /// Sin tiempo entre muestras no hay tasa. Devolver 0 mentiría igual que 100.
    func testNoTimePassedIsUnknown() {
        let ticks = CPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        XCTAssertNil(ticks.usage(since: ticks))
    }

    func testFullyBusyIsHundred() {
        let before = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let after = CPUTicks(user: 500, system: 500, idle: 0, nice: 0)
        XCTAssertEqual(after.usage(since: before)!, 100, accuracy: 0.001)
    }

    func testNiceCountsAsBusy() {
        let before = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let after = CPUTicks(user: 0, system: 0, idle: 50, nice: 50)
        XCTAssertEqual(after.usage(since: before)!, 50, accuracy: 0.001)
    }
}

final class MemoryPressureTests: XCTestCase {
    /// Un Mac con casi toda la memoria ocupada pero sin comprimir va bien: es
    /// exactamente lo que macOS hace a propósito, y asustar por eso sería un fallo.
    func testFullButNotCompressedIsNormal() {
        XCTAssertEqual(MemoryPressure.level(used: 15, compressed: 0.2, total: 16), .warning)
        XCTAssertEqual(MemoryPressure.level(used: 12, compressed: 0.1, total: 16), .normal)
    }

    func testCompressionDrivesTheAlarm() {
        // Poca ocupación, pero comprimiendo mucho: eso sí es presión.
        XCTAssertEqual(MemoryPressure.level(used: 8, compressed: 5, total: 16), .critical)
        XCTAssertEqual(MemoryPressure.level(used: 8, compressed: 2, total: 16), .warning)
    }

    func testAlmostFullIsCritical() {
        XCTAssertEqual(MemoryPressure.level(used: 15.5, compressed: 0, total: 16), .critical)
    }

    func testNoMemoryDoesNotDivideByZero() {
        XCTAssertEqual(MemoryPressure.level(used: 0, compressed: 0, total: 0), .normal)
    }
}

final class RateTests: XCTestCase {
    func testBytesPerSecond() {
        XCTAssertEqual(Rate.perSecond(from: 1_000, to: 3_000, seconds: 2), 1_000, accuracy: 0.001)
    }

    func testZeroSecondsIsZero() {
        XCTAssertEqual(Rate.perSecond(from: 0, to: 1_000, seconds: 0), 0)
    }

    /// Un contador que baja es un contador reiniciado (disco desmontado, interfaz
    /// caída). Restar daría un número enorme por culpa del desbordamiento.
    func testCounterResetGivesZeroNotGarbage() {
        XCTAssertEqual(Rate.perSecond(from: 5_000, to: 10, seconds: 1), 0)
    }
}

final class TopProcessesTests: XCTestCase {
    private func sample(_ pid: pid_t, _ name: String, cpu: Double, memory: Double = 0) -> TopProcesses.Sample {
        .init(pid: pid, name: name, cpuSeconds: cpu, memory: memory)
    }

    func testPercentageOfOneCore() {
        let before = [sample(1, "Xcode", cpu: 10)]
        let after = [sample(1, "Xcode", cpu: 12)]
        // 2 s de CPU en 2 s de reloj = un núcleo entero
        XCTAssertEqual(TopProcesses.cpuUsage(from: before, to: after, seconds: 2).first!.cpu,
                       100, accuracy: 0.001)
    }

    /// Puede pasar del 100 %: un proceso con varios hilos usa varios núcleos, y eso
    /// es justo lo que hay que enseñar (Monitor de Actividad hace lo mismo).
    func testMultipleCoresGoAboveHundred() {
        let usage = TopProcesses.cpuUsage(from: [sample(1, "ffmpeg", cpu: 0)],
                                          to: [sample(1, "ffmpeg", cpu: 4)], seconds: 1)
        XCTAssertEqual(usage.first!.cpu, 400, accuracy: 0.001)
    }

    /// Un proceso recién arrancado no tiene con qué compararse: colarlo con un 0 %
    /// lo metería en la lista sin merecerlo.
    func testNewProcessIsIgnoredUntilItHasHistory() {
        let usage = TopProcesses.cpuUsage(from: [], to: [sample(9, "nuevo", cpu: 5)], seconds: 1)
        XCTAssertTrue(usage.isEmpty)
    }

    /// macOS recicla los números de PID. Si el tiempo de CPU baja, el que está ahí
    /// ya no es el mismo proceso.
    func testRecycledPIDIsDiscarded() {
        let usage = TopProcesses.cpuUsage(from: [sample(1, "viejo", cpu: 900)],
                                          to: [sample(1, "nuevo", cpu: 1)], seconds: 1)
        XCTAssertTrue(usage.isEmpty)
    }

    func testNoTimePassedGivesNothing() {
        XCTAssertTrue(TopProcesses.cpuUsage(from: [sample(1, "a", cpu: 1)],
                                            to: [sample(1, "a", cpu: 2)], seconds: 0).isEmpty)
    }

    func testTopByCPUOrdersAndCuts() {
        let usage = [
            TopProcesses.Usage(pid: 1, name: "poco", cpu: 0.2, memory: 0),
            TopProcesses.Usage(pid: 2, name: "medio", cpu: 12, memory: 0),
            TopProcesses.Usage(pid: 3, name: "mucho", cpu: 80, memory: 0),
        ]
        let top = TopProcesses.topByCPU(usage, limit: 2)
        XCTAssertEqual(top.map(\.name), ["mucho", "medio"])
        // El de 0,2 % queda fuera: una lista de ceros no informa de nada.
        XCTAssertFalse(top.contains { $0.name == "poco" })
    }

    func testTopByMemoryOrders() {
        let usage = [
            TopProcesses.Usage(pid: 1, name: "a", cpu: 0, memory: 100),
            TopProcesses.Usage(pid: 2, name: "b", cpu: 0, memory: 900),
        ]
        XCTAssertEqual(TopProcesses.topByMemory(usage, limit: 1).map(\.name), ["b"])
    }

    /// Con el mismo consumo, por nombre: así la lista no baila entre muestras.
    func testTiesAreStable() {
        let usage = [
            TopProcesses.Usage(pid: 1, name: "Zebra", cpu: 5, memory: 0),
            TopProcesses.Usage(pid: 2, name: "Alfa", cpu: 5, memory: 0),
        ]
        XCTAssertEqual(TopProcesses.topByCPU(usage).map(\.name), ["Alfa", "Zebra"])
    }
}

final class TemperatureTests: XCTestCase {
    /// `tcal` es el sensor de calibración: lee mucho más alto que los demás y
    /// colarlo en la media daría diez grados de más.
    func testCalibrationSensorIsNotTheChip() {
        XCTAssertFalse(Temperature.isSoC("PMU tcal"))
        XCTAssertTrue(Temperature.isSoC("PMU tdie9"))
        XCTAssertTrue(Temperature.isSoC("PMU2 tdev3"))
    }

    func testBatterySensor() {
        XCTAssertTrue(Temperature.isBattery("gas gauge battery"))
        XCTAssertFalse(Temperature.isBattery("PMU tdie1"))
    }

    /// Un sensor dormido devuelve 0: si entrara en la media, la hundiría.
    func testAverageIgnoresSleepingSensors() {
        XCTAssertEqual(Temperature.average([30, 0, 32, 0])!, 31, accuracy: 0.001)
        XCTAssertNil(Temperature.average([0, 0]))
        XCTAssertNil(Temperature.average([]))
    }

    /// Lecturas imposibles fuera: un sensor que dice 900 °C está roto.
    func testAverageIgnoresImpossibleValues() {
        XCTAssertEqual(Temperature.average([30, 900])!, 30, accuracy: 0.001)
    }
}

/// Con los nombres reales de los 47 sensores de un MacBook con Apple silicon.
final class TemperatureReadingTests: XCTestCase {
    private let real: [(name: String, value: Double)] = [
        ("PMU tdie1", 30.4), ("PMU tdie8", 31.2), ("PMU tdev2", 31.1),
        ("PMU2 tdie6", 28.5), ("PMU2 tdev5", 27.9),
        ("PMU tcal", 51.8), ("PMU2 tcal", 51.8),
        ("NAND CH0 temp", 30.0),
        ("gas gauge battery", 26.0), ("gas gauge battery", 26.9),
        ("PMU tdev1", 0),
    ]

    func testAverageIsOnlyTheChipDiodes() {
        let reading = Temperature.reading(from: real)
        // Media de 30,4 · 31,2 · 31,1 · 28,5 · 27,9 — sin tcal, sin NAND, sin batería
        XCTAssertEqual(reading.soc!, 29.82, accuracy: 0.01)
    }

    /// El pico es lo que hace que el Mac baje el reloj, así que va aparte.
    func testPeakIsTheHottestDiode() {
        XCTAssertEqual(Temperature.reading(from: real).socMax!, 31.2, accuracy: 0.01)
    }

    func testSSDAndBatteryAreTheirOwnThing() {
        let reading = Temperature.reading(from: real)
        XCTAssertEqual(reading.ssd!, 30.0, accuracy: 0.01)
        XCTAssertEqual(reading.battery!, 26.9, accuracy: 0.01)
    }

    /// La batería aparece seis veces con el mismo nombre: en la lista va una sola,
    /// con la lectura más alta. Y el sensor dormido (0 °C) no entra.
    func testDuplicatesCollapseAndDeadSensorsAreDropped() {
        let sensors = Temperature.reading(from: real).sensors
        XCTAssertEqual(sensors.filter { $0.name == "gas gauge battery" }.count, 1)
        XCTAssertFalse(sensors.contains { $0.name == "PMU tdev1" })
        // Ordenados de más caliente a menos
        XCTAssertEqual(sensors.first?.name, "PMU tcal")
    }
}
