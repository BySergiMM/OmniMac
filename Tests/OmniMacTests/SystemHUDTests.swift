import XCTest
import AppKit
@testable import OmniMac

/// Teclas de volumen y brillo, el paso del HUD y dónde va el vistazo (issue #4).
final class SystemHUDTests: XCTestCase {

    // MARK: Teclas

    private func data1(_ key: Int, state: Int, repeat isRepeat: Bool = false) -> Int {
        (key << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    func testDecodesVolumeUpPressAndRelease() {
        let down = MediaKeyPress.decode(data1: data1(0, state: 0xA), modifiers: [])
        XCTAssertEqual(down, MediaKeyPress(key: .volumeUp, isDown: true, isRepeat: false, fine: false))
        let up = MediaKeyPress.decode(data1: data1(0, state: 0xB), modifiers: [])
        XCTAssertEqual(up?.isDown, false)
    }

    func testDecodesBrightnessMuteAndRepeat() {
        XCTAssertEqual(MediaKeyPress.decode(data1: data1(3, state: 0xA), modifiers: [])?.key, .brightnessDown)
        XCTAssertEqual(MediaKeyPress.decode(data1: data1(2, state: 0xA), modifiers: [])?.key, .brightnessUp)
        let mute = MediaKeyPress.decode(data1: data1(7, state: 0xA, repeat: true), modifiers: [])
        XCTAssertEqual(mute?.key, .mute)
        XCTAssertEqual(mute?.isRepeat, true)
    }

    func testIgnoresOtherKeysAndStates() {
        // Reproducir/pausar (16) y la retroiluminación (21) siguen siendo de macOS.
        XCTAssertNil(MediaKeyPress.decode(data1: data1(16, state: 0xA), modifiers: []))
        XCTAssertNil(MediaKeyPress.decode(data1: data1(21, state: 0xA), modifiers: []))
        XCTAssertNil(MediaKeyPress.decode(data1: data1(0, state: 0x0), modifiers: []))
    }

    func testFineStepsNeedOptionAndShift() {
        XCTAssertEqual(MediaKeyPress.decode(data1: data1(0, state: 0xA), modifiers: [.option, .shift])?.fine, true)
        XCTAssertEqual(MediaKeyPress.decode(data1: data1(0, state: 0xA), modifiers: [.option])?.fine, false)
    }

    // MARK: Paso

    func testSixteenStepsFromSilenceToFull() {
        var value: Float = 0
        for _ in 0..<16 { value = HUDStep.next(value, up: true, fine: false) }
        XCTAssertEqual(value, 1, accuracy: 0.0001)
        XCTAssertEqual(HUDStep.next(value, up: true, fine: false), 1)
        for _ in 0..<16 { value = HUDStep.next(value, up: false, fine: false) }
        XCTAssertEqual(value, 0, accuracy: 0.0001)
        XCTAssertEqual(HUDStep.next(0, up: false, fine: false), 0)
    }

    func testOffGridValuesSnapToTheGrid() {
        // 0,53 está entre el paso 8 (0,5) y el 9 (0,5625).
        XCTAssertEqual(HUDStep.next(0.53, up: true, fine: false), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(HUDStep.next(0.53, up: false, fine: false), 0.5, accuracy: 0.0001)
    }

    func testFloatNoiseDoesNotSkipAStep() {
        XCTAssertEqual(HUDStep.next(0.49999, up: true, fine: false), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(HUDStep.next(0.50001, up: false, fine: false), 0.4375, accuracy: 0.0001)
    }

    func testFineStepIsAQuarter() {
        XCTAssertEqual(HUDStep.next(0.5, up: true, fine: true), 0.5 + 1 / 64, accuracy: 0.0001)
    }

    func testVolumeSymbols() {
        XCTAssertEqual(HUDReading(kind: .volume, level: 0.8, muted: true).symbol, "speaker.slash.fill")
        XCTAssertEqual(HUDReading(kind: .volume, level: 0, muted: false).symbol, "speaker.slash.fill")
        XCTAssertEqual(HUDReading(kind: .volume, level: 0.2, muted: false).symbol, "speaker.wave.1.fill")
        XCTAssertEqual(HUDReading(kind: .volume, level: 1, muted: false).symbol, "speaker.wave.3.fill")
    }

    // MARK: Colocación del vistazo

    private let notch = CGSize(width: 196, height: 32)

    func testSidesStaysAtMenuBarHeightAndSymmetric() {
        let layout = PeekLayout.make(placement: .sides, notchSize: notch, leadingWidth: 20,
                                     contentWidth: 150, screenWidth: 1512, flare: 14)
        XCTAssertEqual(layout.size.height, notch.height)
        // Dos alas iguales: el negro sigue centrado sobre el notch físico.
        XCTAssertEqual(layout.size.width, notch.width + layout.wing * 2)
        XCTAssertGreaterThanOrEqual(layout.wing, 150)
    }

    func testSidesCapsLongTitles() {
        let layout = PeekLayout.make(placement: .sides, notchSize: notch, leadingWidth: 20,
                                     contentWidth: 900, screenWidth: 1512, flare: 14)
        XCTAssertEqual(layout.wing, PeekLayout.maxWing)
    }

    func testSidesNeverLeavesTheScreen() {
        let layout = PeekLayout.make(placement: .sides, notchSize: notch, leadingWidth: 20,
                                     contentWidth: 900, screenWidth: 500, flare: 14)
        XCTAssertLessThanOrEqual(layout.size.width, 500 - PeekLayout.screenMargin * 2)
    }

    func testBelowKeepsTheOldShape() {
        let layout = PeekLayout.make(placement: .below, notchSize: notch, leadingWidth: 20,
                                     contentWidth: 10, screenWidth: 1512, flare: 14)
        XCTAssertEqual(layout.wing, 0)
        XCTAssertEqual(layout.size.height, notch.height + PeekLayout.belowExtraHeight)
        XCTAssertEqual(layout.size.width, notch.width + 110)
    }
}
