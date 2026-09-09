import Carbon.HIToolbox
import XCTest
@testable import OmniMac

final class ShortcutTests: XCTestCase {

    // MARK: - Cómo se enseña

    func testDisplayUsesAppleOrder() {
        let s = Shortcut(kVK_ANSI_M, controlKey | optionKey | cmdKey)
        XCTAssertEqual(s.display, "⌃⌥⌘M")
    }

    func testDisplayPutsShiftBeforeCommand() {
        let s = Shortcut(kVK_ANSI_V, cmdKey | shiftKey | optionKey)
        XCTAssertEqual(s.display, "⌥⇧⌘V")
    }

    func testDisplayNamesSpecialKeys() {
        XCTAssertEqual(Shortcut(kVK_LeftArrow, controlKey | optionKey).display, "⌃⌥←")
        XCTAssertEqual(Shortcut(kVK_Space, optionKey).display, "⌥␣")
        XCTAssertEqual(Shortcut(kVK_Return, controlKey | optionKey).display, "⌃⌥↩")
        XCTAssertEqual(Shortcut(kVK_Delete, controlKey | optionKey).display, "⌃⌥⌫")
    }

    // MARK: - Qué se puede asignar

    func testNeedsARealModifier() {
        // Sin modificadores la tecla dejaría de escribir en todo el sistema.
        XCTAssertFalse(Shortcut(kVK_ANSI_A, 0).isValid)
        // ⇧A es una «A» mayúscula, no un atajo.
        XCTAssertFalse(Shortcut(kVK_ANSI_A, shiftKey).isValid)
        XCTAssertTrue(Shortcut(kVK_ANSI_A, cmdKey).isValid)
        XCTAssertTrue(Shortcut(kVK_ANSI_A, controlKey | optionKey).isValid)
    }

    func testRejectsKeysWithoutAName() {
        // Si no se sabe cómo enseñarla, no se deja asignar.
        XCTAssertNil(Shortcut.name(for: 999))
        XCTAssertFalse(Shortcut(999, cmdKey).isValid)
    }

    // MARK: - Guardar y leer

    func testRoundTrip() {
        let s = Shortcut(kVK_ANSI_K, controlKey | cmdKey)
        XCTAssertEqual(Shortcut(stored: s.stored), s)
    }

    func testRejectsBrokenStoredValues() {
        XCTAssertNil(Shortcut(stored: ""))
        XCTAssertNil(Shortcut(stored: "40"))
        XCTAssertNil(Shortcut(stored: "cuarenta:4096"))
        XCTAssertNil(Shortcut(stored: "40:4096:2"))
    }

    // MARK: - Modificadores de AppKit → Carbon

    func testTranslatesCocoaModifiers() {
        let control: UInt = 1 << 18, option: UInt = 1 << 19
        let shift: UInt = 1 << 17, command: UInt = 1 << 20
        XCTAssertEqual(Shortcut.carbonModifiers(fromCocoa: control | option),
                       UInt32(controlKey | optionKey))
        XCTAssertEqual(Shortcut.carbonModifiers(fromCocoa: command | shift),
                       UInt32(cmdKey | shiftKey))
        // Bloq Mayús y las teclas de función no cuentan como modificador de atajo.
        XCTAssertEqual(Shortcut.carbonModifiers(fromCocoa: 1 << 16), 0)
    }
}

final class ShortcutStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ShortcutStore!
    private let suite = "omnimac.tests.shortcuts"

    private let ocr = ShortcutBinding(key: "tools.ocr", hotKeyID: 9001, title: "OCR",
                                      fallback: Shortcut(kVK_ANSI_2, cmdKey | shiftKey))
    private let mic = ShortcutBinding(key: "tools.mic", hotKeyID: 9002, title: "Micro",
                                      fallback: Shortcut(kVK_ANSI_M, controlKey | optionKey | cmdKey))

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        store = ShortcutStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFallsBackToTheFactoryValue() {
        XCTAssertEqual(store.shortcut(for: ocr), ocr.fallback)
        XCTAssertTrue(store.isDefault(ocr))
    }

    func testRemembersWhatTheUserChose() {
        let mine = Shortcut(kVK_ANSI_7, controlKey | cmdKey)
        store.set(mine, for: ocr)
        XCTAssertEqual(store.shortcut(for: ocr), mine)
        XCTAssertFalse(store.isDefault(ocr))
    }

    func testEmptyMeansNoShortcutAtAll() {
        // Quitarlo es una decisión válida: el usuario quiere esa combinación para otra app.
        store.set(nil, for: ocr)
        XCTAssertNil(store.shortcut(for: ocr))
        XCTAssertFalse(store.isDefault(ocr))
    }

    func testResetGoesBackToFactory() {
        store.set(Shortcut(kVK_ANSI_7, cmdKey), for: ocr)
        store.reset(ocr)
        XCTAssertEqual(store.shortcut(for: ocr), ocr.fallback)
        XCTAssertTrue(store.isDefault(ocr))
    }

    func testABrokenStoredValueDoesNotBreakTheApp() {
        defaults.set("basura", forKey: "shortcut.tools.ocr")
        XCTAssertEqual(store.shortcut(for: ocr), ocr.fallback)
    }

    // MARK: - Choques

    func testFindsTwoOmniMacActionsFightingForTheSameKeys() {
        store.remember(ocr) {}
        store.remember(mic) {}
        XCTAssertNil(store.conflict(for: ocr))

        store.set(mic.fallback, for: ocr)
        XCTAssertEqual(store.conflict(for: ocr)?.key, mic.key)
        XCTAssertEqual(store.conflict(for: mic)?.key, ocr.key)
    }

    func testNoShortcutNeverConflicts() {
        store.remember(ocr) {}
        store.remember(mic) {}
        store.set(nil, for: ocr)
        store.set(nil, for: mic)
        XCTAssertNil(store.conflict(for: ocr))
    }

    func testCatalogueDoesNotDuplicate() {
        store.remember(ocr) {}
        store.remember(ocr) {}
        XCTAssertEqual(store.catalogue.filter { $0.key == ocr.key }.count, 1)
    }

    // MARK: - Los que se quedaron sin sitio

    func testRemembersWhichOnesAnotherAppTook() {
        XCTAssertFalse(store.isUnavailable(ocr))
        store.markUnavailable(ocr, true)
        XCTAssertTrue(store.isUnavailable(ocr))
        store.markUnavailable(ocr, false)
        XCTAssertFalse(store.isUnavailable(ocr))
    }

    func testChangingAShortcutReRegistersIt() {
        var rebinds = 0
        store.remember(ocr) { rebinds += 1 }
        store.set(Shortcut(kVK_ANSI_7, cmdKey), for: ocr)
        XCTAssertEqual(rebinds, 1)
        store.reset(ocr)
        XCTAssertEqual(rebinds, 2)
    }
}
