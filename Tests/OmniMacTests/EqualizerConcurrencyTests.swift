import XCTest
@testable import OmniMac

/// El ecualizador recibe ganancias nuevas desde el hilo principal mientras el hilo
/// de audio lee sus coeficientes. Estas pruebas hacen lo mismo con dos hilos de
/// verdad: uno publica sin parar y otro lee, y lo leído ha de ser siempre un juego
/// entero de una misma publicación, nunca una mezcla de dos.
final class EqualizerConcurrencyTests: XCTestCase {
    private static let sampleRate = 48_000.0

    /// Niveles que publica el escritor: las diez bandas al mismo valor, para poder
    /// saber de qué publicación viene lo que ve el lector. El 0 es el caso «plano».
    private static let levels: [Double] = [0, 6, -6, 12, -12, 3]

    private static func gains(level: Double) -> [Double] {
        [Double](repeating: level, count: EqualizerBands.count)
    }

    /// Los diez filtros que debe dar un nivel, calculados por separado con la misma
    /// receta: si el lector ve otra cosa, es que vio media publicación.
    private static func expectedFilters(level: Double) -> [Biquad] {
        EqualizerBands.frequencies.map {
            Biquad.peaking(frequency: $0, gainDB: level, sampleRate: sampleRate)
        }
    }

    /// Marca para avisar al lector de que el escritor ha terminado.
    private final class Finished: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    /// Lanza el escritor en su propio hilo (así avanza aunque el Mac esté ocupado) y
    /// devuelve cuando ha empezado.
    private func startWriter(_ equalizer: Equalizer, publications: Int,
                             finished: Finished, done: DispatchSemaphore) {
        let sets = Self.levels.map { Self.gains(level: $0) }
        let rate = Self.sampleRate
        let started = DispatchSemaphore(value: 0)
        let writer = Thread {
            started.signal()
            for index in 0..<publications {
                equalizer.setGains(sets[index % sets.count], sampleRate: rate)
            }
            finished.set()
            done.signal()
        }
        writer.start()
        started.wait()
    }

    func testTheReaderNeverSeesAHalfPublishedSet() {
        let equalizer = Equalizer()
        equalizer.setGains(Self.gains(level: Self.levels[0]), sampleRate: Self.sampleRate)
        let expected = Self.levels.map { Self.expectedFilters(level: $0) }
        let flatLevels = Self.levels.map { $0 == 0 }

        let finished = Finished()
        let done = DispatchSemaphore(value: 0)
        startWriter(equalizer, publications: 100_000, finished: finished, done: done)

        var reads = 0
        var torn = 0
        while !finished.isSet {
            let seen = equalizer.publishedForTesting()
            reads += 1
            // Tiene que ser exactamente uno de los juegos publicados, con su marca de
            // plano: coeficientes de una publicación y marca de otra también es fallo.
            let whole = expected.indices.contains { index in
                expected[index] == seen.filters && flatLevels[index] == seen.isFlat
            }
            if !whole { torn += 1 }
        }
        done.wait()

        XCTAssertGreaterThan(reads, 0)
        XCTAssertEqual(torn, 0, "el lector vio un juego de coeficientes a medias (\(torn) de \(reads) lecturas)")
        // Terminado el escritor, lo último que publicó es lo que se lee.
        let last = Self.levels[(100_000 - 1) % Self.levels.count]
        XCTAssertEqual(equalizer.publishedForTesting().filters, Self.expectedFilters(level: last))
    }

    func testProcessingWhileTheGainsChangeStaysFinite() {
        // Lo mismo, pero filtrando audio de verdad mientras se publican ganancias.
        let equalizer = Equalizer()
        equalizer.setGains(Self.gains(level: Self.levels[0]), sampleRate: Self.sampleRate)
        let finished = Finished()
        let done = DispatchSemaphore(value: 0)
        startWriter(equalizer, publications: 50_000, finished: finished, done: done)

        let block: [Float] = (0..<512).map {
            Float(0.9 * sin(2 * Double.pi * 440 * Double($0) / Self.sampleRate))
        }
        var samples = block
        var blocks = 0
        var misbehaved = 0
        while !finished.isSet {
            samples = block
            samples.withUnsafeMutableBufferPointer { buffer in
                equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
            }
            blocks += 1
            let peak = samples.map { abs($0) }.max() ?? 0
            if !samples.allSatisfy({ $0.isFinite }) || peak > 60 { misbehaved += 1 }
        }
        done.wait()

        XCTAssertGreaterThan(blocks, 0)
        XCTAssertEqual(misbehaved, 0, "el filtro se desbocó con ganancias cambiando (\(misbehaved) de \(blocks) bloques)")
    }

    // MARK: - El buzón con un solo hilo

    func testALaterPublicationReplacesAnUnreadOne() {
        // Si el lector no ha recogido nada entre dos publicaciones, se queda con la última.
        let equalizer = Equalizer()
        equalizer.setGains(Self.gains(level: 6), sampleRate: Self.sampleRate)
        equalizer.setGains(Self.gains(level: -6), sampleRate: Self.sampleRate)
        equalizer.setGains(Self.gains(level: 12), sampleRate: Self.sampleRate)
        XCTAssertEqual(equalizer.publishedForTesting().filters, Self.expectedFilters(level: 12))
    }

    func testReadingWithoutNewsKeepsTheSameSet() {
        let equalizer = Equalizer()
        equalizer.setGains(Self.gains(level: 6), sampleRate: Self.sampleRate)
        let first = equalizer.publishedForTesting()
        for _ in 0..<5 {
            let again = equalizer.publishedForTesting()
            XCTAssertEqual(again.filters, first.filters)
            XCTAssertEqual(again.isFlat, first.isFlat)
        }
    }

    func testReadingBetweenPublicationsFollowsEachOne() {
        let equalizer = Equalizer()
        for level in Self.levels + Self.levels.reversed() {
            equalizer.setGains(Self.gains(level: level), sampleRate: Self.sampleRate)
            let seen = equalizer.publishedForTesting()
            XCTAssertEqual(seen.filters, Self.expectedFilters(level: level), "nivel \(level)")
            XCTAssertEqual(seen.isFlat, level == 0, "nivel \(level)")
        }
    }

    func testTheFlatMarkTravelsWithItsSet() {
        let equalizer = Equalizer()
        XCTAssertTrue(equalizer.isFlat, "recién creado, sin ganancias")
        equalizer.setGains(Self.gains(level: 6), sampleRate: Self.sampleRate)
        XCTAssertFalse(equalizer.isFlat)
        equalizer.setGains(Self.gains(level: 0), sampleRate: Self.sampleRate)
        XCTAssertTrue(equalizer.isFlat)
        XCTAssertEqual(equalizer.publishedForTesting().filters, [Biquad](repeating: .identity, count: EqualizerBands.count))
    }
}
