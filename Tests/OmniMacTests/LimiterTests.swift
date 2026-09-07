import XCTest
@testable import OmniMac

/// El limitador que evita el recorte al amplificar por encima del 100 %.
final class LimiterTests: XCTestCase {

    /// Procesa un bloque de muestras todas iguales y devuelve el resultado.
    private func run(_ value: Float, blocks: Int, limiter: inout Limiter) -> [Float] {
        var samples = [Float](repeating: value, count: 64)
        for _ in 0..<blocks {
            samples = [Float](repeating: value, count: 64)
            samples.withUnsafeMutableBufferPointer { buffer in
                limiter.process(buffer.baseAddress!, stride: 1, count: buffer.count)
            }
        }
        return samples
    }

    func testQuietAudioIsLeftAlone() {
        var limiter = Limiter()
        let out = run(0.3, blocks: 20, limiter: &limiter)
        XCTAssertEqual(out.first!, 0.3, accuracy: 0.0001)
        XCTAssertEqual(limiter.gain, 1, accuracy: 0.0001)
    }

    func testLoudAudioIsBroughtUnderTheCeiling() {
        var limiter = Limiter()
        let out = run(2.5, blocks: 40, limiter: &limiter)   // 250 %: se pasa de largo
        XCTAssertLessThanOrEqual(out.first!, Limiter.ceiling + 0.001)
        XCTAssertLessThan(limiter.gain, 1)
    }

    func testItReactsOnTheFirstBlock() {
        // Un solo bloque ya tiene que bajar bastante: si tardara, se colaría el
        // crujido justo en el golpe fuerte.
        var limiter = Limiter()
        let out = run(4.0, blocks: 1, limiter: &limiter)
        XCTAssertLessThan(out.first!, 4.0)
        XCTAssertLessThan(limiter.gain, 1)
    }

    func testItComesBackUpWhenTheLoudPartEnds() {
        var limiter = Limiter()
        _ = run(3.0, blocks: 40, limiter: &limiter)
        let reduced = limiter.gain
        XCTAssertLessThan(reduced, 1)
        _ = run(0.2, blocks: 400, limiter: &limiter)
        XCTAssertGreaterThan(limiter.gain, reduced, "tiene que ir volviendo a 1")
    }

    func testSilenceDoesNotDivideByZero() {
        var limiter = Limiter()
        let out = run(0, blocks: 5, limiter: &limiter)
        XCTAssertEqual(out.first!, 0)
        XCTAssertFalse(limiter.gain.isNaN)
    }

    func testResetGoesBackToNormal() {
        var limiter = Limiter()
        _ = run(3.0, blocks: 30, limiter: &limiter)
        limiter.reset()
        XCTAssertEqual(limiter.gain, 1)
    }
}
