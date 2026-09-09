import Carbon.HIToolbox

/// Una combinación de teclas: el código de tecla de Carbon y sus modificadores.
///
/// Se guarda como texto («46:4864») porque UserDefaults no entiende de structs y
/// porque así se puede leer y arreglar a mano si algo se tuerce.
struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(_ keyCode: Int, _ modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: - Guardar y leer

    var stored: String { "\(keyCode):\(modifiers)" }

    init?(stored: String) {
        let parts = stored.split(separator: ":")
        guard parts.count == 2,
              let key = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        self.keyCode = key
        self.modifiers = mods
    }

    // MARK: - Qué vale como atajo global

    /// Un atajo global necesita al menos un modificador **que no sea solo ⇧**.
    ///
    /// Sin esto se podría capturar la «A» a secas y dejar el teclado inservible: la
    /// tecla dejaría de escribir en todas las apps. ⇧ sola tampoco basta, porque ⇧A
    /// es simplemente una «A» mayúscula.
    var isValid: Bool {
        let real = modifiers & UInt32(controlKey | optionKey | cmdKey)
        return real != 0 && Self.name(for: keyCode) != nil
    }

    // MARK: - Cómo se enseña

    /// El orden de los modificadores es el de Apple: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + (Self.name(for: keyCode) ?? "?")
    }

    /// Nombre visible de cada tecla. Solo las que tienen sentido como atajo: si una
    /// tecla no está aquí, `isValid` la rechaza y no se puede asignar.
    static func name(for keyCode: UInt32) -> String? {
        if let special = specialNames[Int(keyCode)] { return special }
        return letterNames[Int(keyCode)]
    }

    private static let specialNames: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Space: "␣", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Minus: "−", kVK_ANSI_Equal: "=", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Grave: "`",
    ]

    private static let letterNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]

    /// Traduce los modificadores de AppKit (`NSEvent.ModifierFlags`) a los de Carbon,
    /// que es lo que entiende `RegisterEventHotKey`.
    static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var out: UInt32 = 0
        if flags & (1 << 18) != 0 { out |= UInt32(controlKey) }    // .control
        if flags & (1 << 19) != 0 { out |= UInt32(optionKey) }     // .option
        if flags & (1 << 17) != 0 { out |= UInt32(shiftKey) }      // .shift
        if flags & (1 << 20) != 0 { out |= UInt32(cmdKey) }        // .command
        return out
    }
}

/// Un atajo que el usuario puede cambiar: dónde se guarda, cómo se llama y cuál es
/// el de fábrica.
///
/// Vive junto al módulo que lo usa y no en una lista central: así, al leer el código
/// de una función, el atajo está a la vista y no en otro archivo.
struct ShortcutBinding {
    /// Clave estable en UserDefaults. No cambiarla nunca: es lo que ata la
    /// preferencia del usuario a esta acción.
    let key: String
    /// Identificador numérico para Carbon. Único en toda la app.
    let hotKeyID: UInt32
    /// Qué hace, para enseñarlo en Ajustes. Ya viene traducido.
    let title: String
    /// El de fábrica.
    let fallback: Shortcut
}
