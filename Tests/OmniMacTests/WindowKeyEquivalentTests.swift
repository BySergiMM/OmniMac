import AppKit
import XCTest
@testable import OmniMac

/// El ⌘W que cierra Ajustes y Novedades. Sin `NSApp.mainMenu` no hay ningún menú
/// Archivo que lo traduzca, así que lo decide esto y conviene tenerlo atado.
final class WindowKeyEquivalentTests: XCTestCase {

    func testCommandWCloses() {
        XCTAssertTrue(WindowKeyEquivalent.isClose(modifiers: [.command], characters: "w"))
    }

    func testIgnoresCapsLockAndFunctionKeys() {
        // Flags que macOS cuela sin que el usuario haya pulsado otro modificador.
        XCTAssertTrue(WindowKeyEquivalent.isClose(modifiers: [.command, .capsLock], characters: "w"))
        XCTAssertTrue(WindowKeyEquivalent.isClose(modifiers: [.command, .function, .numericPad], characters: "w"))
        // Con Bloq Mayús el carácter llega en mayúscula.
        XCTAssertTrue(WindowKeyEquivalent.isClose(modifiers: [.command, .capsLock], characters: "W"))
    }

    func testNeedsTheCommandKey() {
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [], characters: "w"))
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.control], characters: "w"))
    }

    func testOtherModifiersAreSomebodyElsesShortcut() {
        // ⌥⌘W es «cerrar todas las ventanas», que aquí no existe: mejor no hacer nada
        // que cerrar una sola y que parezca que funciona.
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command, .option], characters: "w"))
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command, .shift], characters: "w"))
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command, .control], characters: "w"))
    }

    func testLeavesOtherKeysAlone() {
        // ⌘Q sale de la app y ⌘, abre Ajustes: los sirve el menú de la barra, no esto.
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command], characters: "q"))
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command], characters: ","))
        XCTAssertFalse(WindowKeyEquivalent.isClose(modifiers: [.command], characters: nil))
    }

    // MARK: - Con eventos de verdad

    private func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ chars: String) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 13)!
    }

    func testReadsTheKeyWithoutModifiers() {
        XCTAssertTrue(WindowKeyEquivalent.isClose(event(.keyDown, [.command], "w")))
        // Al soltar no se cierra dos veces.
        XCTAssertFalse(WindowKeyEquivalent.isClose(event(.keyUp, [.command], "w")))
    }
}
