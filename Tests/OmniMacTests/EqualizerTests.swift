import XCTest
@testable import OmniMac

/// El ecualizador, comprobado con señales de verdad: se genera un tono, se filtra y
/// se mide cuánto ha subido o bajado. Así se ve si hace lo que dice sin tener que
/// poner música alta.
final class EqualizerTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// Un tono puro de la frecuencia pedida.
    private func tone(_ frequency: Double, samples: Int = 24_000) -> [Float] {
        (0..<samples).map { Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// Nivel eficaz, saltándose el arranque del filtro (que aún se está asentando).
    private func rms(_ values: [Float], skip: Int = 4_000) -> Double {
        let tail = values.dropFirst(skip)
        guard !tail.isEmpty else { return 0 }
        let total = tail.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (total / Double(tail.count)).squareRoot()
    }

    /// Cuántos decibelios cambia un tono al pasar por el ecualizador.
    private func change(frequency: Double, gains: [Double]) -> Double {
        let equalizer = Equalizer()
        equalizer.setGains(gains, sampleRate: sampleRate)
        var samples = tone(frequency)
        let before = rms(samples)
        samples.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        let after = rms(samples)
        return 20 * log10(after / before)
    }

    private func gains(_ band: Int, _ value: Double) -> [Double] {
        var all = [Double](repeating: 0, count: EqualizerBands.count)
        all[band] = value
        return all
    }

    func testFlatEqualizerLeavesTheSoundAlone() {
        let equalizer = Equalizer()
        equalizer.setGains([Double](repeating: 0, count: EqualizerBands.count), sampleRate: sampleRate)
        XCTAssertTrue(equalizer.isFlat)

        var samples = tone(1_000)
        let original = samples
        samples.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        XCTAssertEqual(samples, original)
    }

    func testBoostingABandRaisesThatTone() {
        // Banda 5 = 1 kHz, +6 dB.
        let db = change(frequency: 1_000, gains: gains(5, 6))
        XCTAssertEqual(db, 6, accuracy: 0.7, "un tono de 1 kHz con +6 dB debe subir unos 6 dB")
    }

    func testCuttingABandLowersThatTone() {
        let db = change(frequency: 1_000, gains: gains(5, -6))
        XCTAssertEqual(db, -6, accuracy: 0.7)
    }

    func testTheRestOfTheSpectrumIsLeftAlone() {
        // Subir 1 kHz no puede levantar los agudos ni los graves lejanos.
        XCTAssertEqual(change(frequency: 16_000, gains: gains(5, 12)), 0, accuracy: 1.0)
        XCTAssertEqual(change(frequency: 32, gains: gains(5, 12)), 0, accuracy: 1.0)
    }

    func testEveryBandActsOnItsOwnFrequency() {
        for band in 0..<EqualizerBands.count {
            let frequency = EqualizerBands.frequencies[band]
            let db = change(frequency: frequency, gains: gains(band, 6))
            XCTAssertEqual(db, 6, accuracy: 1.2, "la banda de \(Int(frequency)) Hz no sube su propio tono")
        }
    }

    func testTheCurveMatchesWhatIsAsked() {
        for db in [-12.0, -6, 6, 12] {
            let filter = Biquad.peaking(frequency: 1_000, gainDB: db, sampleRate: sampleRate)
            let measured = 20 * log10(filter.magnitude(at: 1_000, sampleRate: sampleRate))
            XCTAssertEqual(measured, db, accuracy: 0.2)
        }
    }

    func testZeroGainIsAPassThroughFilter() {
        XCTAssertEqual(Biquad.peaking(frequency: 1_000, gainDB: 0, sampleRate: sampleRate), .identity)
        // Y nada por encima de la mitad de la frecuencia de muestreo.
        XCTAssertEqual(Biquad.peaking(frequency: 30_000, gainDB: 6, sampleRate: sampleRate), .identity)
    }

    func testItNeverBlowsUp() {
        // Todas las bandas al máximo y una señal fuerte: ni infinitos ni NaN.
        let equalizer = Equalizer()
        equalizer.setGains([Double](repeating: EqualizerBands.limitDB, count: EqualizerBands.count), sampleRate: sampleRate)
        var samples = tone(440, samples: 48_000).map { $0 * 0.9 }
        samples.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "el filtro se ha ido a infinito")
        XCTAssertLessThan(samples.map { abs($0) }.max() ?? 0, 60, "ganancia desbocada")
    }

    func testChannelsDoNotMixTheirMemory() {
        // Cada canal lleva su propia memoria: filtrar el izquierdo no puede alterar
        // lo que sale por el derecho.
        let equalizer = Equalizer()
        equalizer.setGains(gains(5, 9), sampleRate: sampleRate)
        var left = tone(1_000, samples: 8_000)
        var right = left
        left.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        right.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 1)
        }
        XCTAssertEqual(rms(left), rms(right), accuracy: 0.0001)
    }

    func testResetForgetsThePreviousAudio() {
        let equalizer = Equalizer()
        equalizer.setGains(gains(5, 12), sampleRate: sampleRate)
        var loud = tone(1_000, samples: 4_000).map { $0 * 0.9 }
        loud.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        equalizer.reset()
        // Tras el reset, un bloque de silencio tiene que salir en silencio.
        var silence = [Float](repeating: 0, count: 512)
        silence.withUnsafeMutableBufferPointer { buffer in
            equalizer.process(buffer.baseAddress!, stride: 1, count: buffer.count, channel: 0)
        }
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
    }
}
