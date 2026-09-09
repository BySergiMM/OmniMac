import XCTest
@testable import OmniMac

/// Pruebas de la lógica pura (sin ventanas ni permisos).
final class TimerTests: XCTestCase {
    override class func setUp() { setenv("OMNIMAC_LANG", "es", 1) }
    override func tearDown() {
        NotchTimer.shared.stop()
        NotchTimer.shared.presets = [5, 10, 25, 45, 60]
    }

    func testPresetsTextParsesNumbersAndIgnoresJunk() {
        let timer = NotchTimer.shared
        timer.presetsText = "3, 7 · 12 y 900 y 0"
        XCTAssertEqual(timer.presets, [3, 7, 12])        // 900 y 0 fuera de rango
        XCTAssertEqual(timer.presetsText, "3, 7, 12")
    }

    func testPresetsTextKeepsAtMostSixAndIgnoresEmpty() {
        let timer = NotchTimer.shared
        timer.presetsText = "1,2,3,4,5,6,7,8"
        XCTAssertEqual(timer.presets, [1, 2, 3, 4, 5, 6])
        timer.presetsText = "nada"
        XCTAssertEqual(timer.presets, [1, 2, 3, 4, 5, 6])   // sin números → no cambia
    }

    func testStartFormatsRemainingAndPhase() {
        let timer = NotchTimer.shared
        timer.start(minutes: 25)
        XCTAssertTrue(timer.isSet)
        XCTAssertTrue(timer.running)
        XCTAssertEqual(timer.remainingText, "25:00")
        XCTAssertEqual(timer.phaseText, "Temporizador")
        timer.pause()
        XCTAssertFalse(timer.running)
        timer.stop()
        XCTAssertFalse(timer.isSet)
        XCTAssertEqual(timer.remainingText, "00:00")
    }

    func testPomodoroStartsWithWorkMinutes() {
        let timer = NotchTimer.shared
        let work = timer.workMinutes
        timer.startPomodoro()
        XCTAssertEqual(timer.remainingText, String(format: "%02d:00", work))
        XCTAssertEqual(timer.phaseText, "Trabajo · pomodoro 1")
    }
}

final class LayoutTests: XCTestCase {
    func testLayoutRoundTripsThroughJSON() throws {
        let entry = WindowLayout.Entry(bundleID: "com.apple.Safari", appName: "Safari", title: "Apple",
                                       x: 10, y: 20, width: 800, height: 600)
        let layout = WindowLayout(name: "Trabajo", screenCount: 2, savedAt: Date(timeIntervalSince1970: 0),
                                  windows: [entry], hotKey: 3)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(WindowLayout.self, from: data)
        XCTAssertEqual(decoded.id, layout.id)
        XCTAssertEqual(decoded.name, "Trabajo")
        XCTAssertEqual(decoded.hotKey, 3)
        XCTAssertEqual(decoded.screenCount, 2)
        XCTAssertEqual(decoded.windows.first?.frame, CGRect(x: 10, y: 20, width: 800, height: 600))
        XCTAssertEqual(decoded.appCount, 1)
    }

    func testShortcutLabel() {
        // El rótulo ya no se escribe a mano: sale del atajo de verdad, que el usuario
        // puede haber cambiado. Por eso lo dibuja `Shortcut.display`, sin espacio.
        let base = WindowLayout(name: "a", screenCount: 1, savedAt: Date(), windows: [], hotKey: 1)
        XCTAssertEqual(base.shortcutLabel, "⌃⌥1")
        var free = base
        free.hotKey = nil
        XCTAssertNil(free.shortcutLabel)
        // Un número fuera de 1…9 no tiene atajo que enseñar.
        var broken = base
        broken.hotKey = 42
        XCTAssertNil(broken.shortcutLabel)
    }
}

final class MiscTests: XCTestCase {
    override class func setUp() { setenv("OMNIMAC_LANG", "es", 1) }
    func testToastStyleTitles() {
        XCTAssertEqual(ToastStyle.bottom.title, "Abajo de la pantalla")
        XCTAssertEqual(ToastStyle.notch.title, "Desplegando el notch")
        XCTAssertEqual(ToastStyle(rawValue: 7), nil)
    }

    func testBrandLinks() {
        XCTAssertEqual(Brand.coffeeURL.host, "ko-fi.com")
        XCTAssertEqual(Brand.sponsorsURL.host, "github.com")
    }

    func testNotchTabsPerformanceGoesRight() {
        XCTAssertFalse(NotchTab.leftTabs.contains(.performance))
        XCTAssertEqual(Set(NotchTab.leftTabs).union([.performance]), Set(NotchTab.allCases))
    }
}

final class CacheCleanerTests: XCTestCase {
    override class func setUp() { setenv("OMNIMAC_LANG", "es", 1) }

    func testDirectorySizeSumsRegularFilesRecursively() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omnimac-cache-test-\(UUID().uuidString)")
        let inner = root.appendingPathComponent("fsCachedData", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data(count: 1500).write(to: root.appendingPathComponent("Cache.db"))
        try Data(count: 2500).write(to: inner.appendingPathComponent("A"))
        try Data(count: 4000).write(to: inner.appendingPathComponent("B"))
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(CacheCleaner.directorySize(root), 8000)
        XCTAssertEqual(CacheCleaner.directorySize(root.appendingPathComponent("no-existe")), 0)
    }

    func testFormatUsesFileStyle() {
        XCTAssertFalse(CacheCleaner.format(0).isEmpty)
        XCTAssertTrue(CacheCleaner.format(12_300_000).contains("MB"))
    }
}
