import XCTest
@testable import OmniMac

/// El porcentaje de batería de los AirPods, tal como lo escribe `system_profiler`.
final class HeadphonesBatteryTests: XCTestCase {
    /// macOS 27 mete un espacio duro (U+00A0) antes del `%`: la batería no salía.
    func testEspacioDuroDeMacOS27() {
        XCTAssertEqual(HeadphonesWatcher.battery("100\u{00a0}%"), 100)
        XCTAssertEqual(HeadphonesWatcher.battery("85\u{00a0}%"), 85)
        XCTAssertEqual(HeadphonesWatcher.battery("5\u{00a0}%"), 5)
    }

    /// Y los formatos de siempre siguen valiendo.
    func testFormatosAntiguos() {
        XCTAssertEqual(HeadphonesWatcher.battery("90%"), 90)
        XCTAssertEqual(HeadphonesWatcher.battery("90 %"), 90)
        XCTAssertEqual(HeadphonesWatcher.battery("0%"), 0)
    }

    /// Sin cifras, nada.
    func testSinBateria() {
        XCTAssertNil(HeadphonesWatcher.battery(nil))
        XCTAssertNil(HeadphonesWatcher.battery("%"))
        XCTAssertNil(HeadphonesWatcher.battery("N/A"))
        XCTAssertNil(HeadphonesWatcher.battery(42))
    }
}
