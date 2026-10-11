import AppKit
import XCTest
@testable import OmniMac

/// La barra de la música entre una consulta a Spotify y la siguiente.
final class TrackClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testAdvancesEverySecondWhilePlaying() {
        let clock = TrackClock(base: 36, at: t0)
        XCTAssertEqual(clock.position(now: t0, playing: true, duration: 179), 36)
        XCTAssertEqual(clock.position(now: t0.addingTimeInterval(1.2), playing: true, duration: 179), 37)
        XCTAssertEqual(clock.position(now: t0.addingTimeInterval(2.9), playing: true, duration: 179), 38)
    }

    func testStandsStillWhenPaused() {
        let clock = TrackClock(base: 36, at: t0)
        XCTAssertEqual(clock.position(now: t0.addingTimeInterval(10), playing: false, duration: 179), 36)
    }

    func testNeverPassesTheEnd() {
        let clock = TrackClock(base: 177, at: t0)
        XCTAssertEqual(clock.position(now: t0.addingTimeInterval(9), playing: true, duration: 179), 179)
    }

    /// Lo que tarda Spotify en contestar no se corrige: corregirlo es el reajuste que se veía.
    func testSmallDifferencesAreNotCorrected() {
        let clock = TrackClock(base: 36, at: t0)
        let now = t0.addingTimeInterval(2.1)   // se enseña 38,1
        XCTAssertEqual(clock.rebased(reported: 37.9, now: now, playing: true, duration: 179), clock)
        XCTAssertEqual(clock.rebased(reported: 38.5, now: now, playing: true, duration: 179), clock)
        // Un segundo de verdad sí (por ejemplo, la red se paró un momento).
        XCTAssertEqual(clock.rebased(reported: 37, now: now, playing: true, duration: 179).base, 37)
    }

    /// Pausar y seguir: la barra se queda donde iba y sigue desde ahí, sin retroceder.
    func testPauseAndResumeKeepTheExactPosition() {
        let playing = TrackClock(base: 53, at: t0)
        let pausedAt = t0.addingTimeInterval(0.6)            // iba por 53,6
        let paused = TrackClock(base: playing.exactPosition(now: pausedAt, playing: true, duration: 216), at: pausedAt)
        XCTAssertEqual(paused.exactPosition(now: pausedAt.addingTimeInterval(5), playing: false, duration: 216), 53.6, accuracy: 0.001)
        // Spotify, ya en pausa, dice 53,72 (aplicó la pausa un poco más tarde): no se toca.
        XCTAssertEqual(paused.rebased(reported: 53.72, now: pausedAt.addingTimeInterval(1), playing: false, duration: 216), paused)
        let resumedAt = pausedAt.addingTimeInterval(5)
        let resumed = TrackClock(base: paused.exactPosition(now: resumedAt, playing: false, duration: 216), at: resumedAt)
        XCTAssertEqual(resumed.exactPosition(now: resumedAt.addingTimeInterval(0.4), playing: true, duration: 216), 54.0, accuracy: 0.001)
    }

    /// Saltar a otro punto (o cambiar de canción) sí mueve la barra al momento.
    func testRealJumpsApply() {
        let clock = TrackClock(base: 36, at: t0)
        let now = t0.addingTimeInterval(2.1)
        XCTAssertEqual(clock.rebased(reported: 120, now: now, playing: true, duration: 179), TrackClock(base: 120, at: now))
        XCTAssertEqual(clock.rebased(reported: 0, now: now, playing: true, duration: 210), TrackClock(base: 0, at: now))
    }

    /// La posición con decimales, de la que arranca el deslizamiento de la barra.
    func testExactPositionForTheSmoothBar() {
        let clock = TrackClock(base: 36, at: t0)
        XCTAssertEqual(clock.exactPosition(now: t0.addingTimeInterval(1.25), playing: true, duration: 179), 37.25, accuracy: 0.001)
        XCTAssertEqual(clock.exactPosition(now: t0.addingTimeInterval(9), playing: false, duration: 179), 36)
        XCTAssertEqual(clock.exactPosition(now: t0.addingTimeInterval(500), playing: true, duration: 179), 179)
    }
}

/// El relleno de la barra, que se desliza con Core Animation.
final class SmoothProgressFillTests: XCTestCase {
    /// Lo que pinta la capa, sin animar, en una barra de 400 × 4.
    @MainActor private func paintedRange(after configurations: [(Int, Int)]) -> ClosedRange<Int>? {
        let view = SmoothProgressFill.FillView(frame: NSRect(x: 0, y: 0, width: 400, height: 4))
        for (position, duration) in configurations {
            view.configure(.init(clock: TrackClock(base: Double(position), at: Date()), duration: duration, playing: false))
            view.layout()
        }
        let ctx = CGContext(data: nil, width: 400, height: 4, bitsPerComponent: 8, bytesPerRow: 1600,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        view.layer!.render(in: ctx)
        let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let lit = (0..<400).filter { pixels[2 * 1600 + $0 * 4 + 3] > 128 }
        guard let first = lit.first, let last = lit.last else { return nil }
        return first...last
    }

    @MainActor func testPaintsTheElapsedPartFromTheLeft() {
        XCTAssertEqual(paintedRange(after: [(50, 200)]), 0...99)
    }

    /// Cada corrección de Spotify vuelve a configurarla. Asignar el marco con el
    /// desplazamiento anterior puesto la dejaba casi llena.
    @MainActor func testStaysRightWhenReconfigured() {
        XCTAssertEqual(paintedRange(after: [(50, 200), (51, 200), (50, 200)]), 0...99)
        XCTAssertEqual(paintedRange(after: [(150, 200), (20, 200)]), 0...39)
    }
}
