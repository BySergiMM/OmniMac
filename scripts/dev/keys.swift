import AppKit

// Teclas sintéticas para probar atajos globales. Uso:
//   swift scripts/dev/keys.swift cmdtab <n> [segundosEntreTabs]   mantiene ⌘, pulsa Tab n veces y suelta
//   swift scripts/dev/keys.swift combo ctrl+alt+right               una combinación (ctrl, alt, shift, cmd + tecla)
//   swift scripts/dev/keys.swift type hola                          escribe texto
let keyCodes: [String: CGKeyCode] = ["tab": 48, "right": 124, "left": 123, "up": 126, "down": 125, "return": 36, "escape": 53, "space": 49,
                                     "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
                                     "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46]
let source = CGEventSource(stateID: .hidSystemState)
func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
    var all = flags
    // Las flechas reales llevan los flags fn y teclado numérico; sin ellos algunos
    // atajos globales (los de ventanas) no las reconocen.
    if [123, 124, 125, 126].contains(code) { all.insert(.maskSecondaryFn); all.insert(.maskNumericPad) }
    e.flags = all
    e.post(tap: .cghidEventTap)
}
let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "cmdtab":
    let n = a.count > 2 ? Int(a[2]) ?? 1 : 1
    let gap = a.count > 3 ? Double(a[3]) ?? 0.7 : 0.7
    post(55, down: true, flags: .maskCommand)                 // ⌘ pulsado
    usleep(120_000)
    for _ in 0..<n { post(48, down: true, flags: .maskCommand); usleep(60_000); post(48, down: false, flags: .maskCommand); Thread.sleep(forTimeInterval: gap) }
    post(55, down: false)                                      // suelta ⌘ → elige
case "combo":
    let parts = a[2].split(separator: "+").map { String($0).lowercased() }
    var flags: CGEventFlags = []
    var codes: [CGKeyCode] = []
    for p in parts {
        switch p {
        case "ctrl", "control": flags.insert(.maskControl); codes.append(59)
        case "alt", "option", "opt": flags.insert(.maskAlternate); codes.append(58)
        case "shift": flags.insert(.maskShift); codes.append(56)
        case "cmd", "command": flags.insert(.maskCommand); codes.append(55)
        default: guard let c = keyCodes[p] else { print("tecla desconocida \(p)"); exit(1) }; codes.append(c)
        }
    }
    let modifiers = codes.dropLast(), key = codes.last!
    for m in modifiers { post(m, down: true, flags: flags); usleep(40_000) }
    post(key, down: true, flags: flags); usleep(80_000); post(key, down: false, flags: flags)
    for m in modifiers.reversed() { usleep(40_000); post(m, down: false) }
case "seq":
    // Secuencia de pasos: cmd-down cmd-up tab type:texto wait:segundos combo:ctrl+alt+right
    var held: CGEventFlags = []
    for step in a.dropFirst(2) {
        if step == "cmd-down" { held.insert(.maskCommand); post(55, down: true, flags: held) }
        else if step == "cmd-up" { held.remove(.maskCommand); post(55, down: false) }
        else if step == "tab" { post(48, down: true, flags: held); usleep(60_000); post(48, down: false, flags: held) }
        else if step.hasPrefix("wait:") { Thread.sleep(forTimeInterval: Double(step.dropFirst(5)) ?? 1) }
        else if step.hasPrefix("type:") { for ch in step.dropFirst(5).lowercased() { if let c = keyCodes[String(ch)] { post(c, down: true, flags: held); usleep(50_000); post(c, down: false, flags: held); usleep(140_000) } } }
        else if step.hasPrefix("combo:") {
            var flags: CGEventFlags = []; var codes: [CGKeyCode] = []
            for p in step.dropFirst(6).split(separator: "+").map({ String($0).lowercased() }) {
                switch p {
                case "ctrl": flags.insert(.maskControl); codes.append(59)
                case "alt": flags.insert(.maskAlternate); codes.append(58)
                case "shift": flags.insert(.maskShift); codes.append(56)
                case "cmd": flags.insert(.maskCommand); codes.append(55)
                default: if let c = keyCodes[p] { codes.append(c) }
                }
            }
            guard let key = codes.last else { continue }
            for m in codes.dropLast() { post(m, down: true, flags: flags); usleep(40_000) }
            post(key, down: true, flags: flags); usleep(80_000); post(key, down: false, flags: flags)
            for m in codes.dropLast().reversed() { usleep(40_000); post(m, down: false) }
        }
        usleep(30_000)
    }
case "type":
    for ch in a[2].lowercased() { if let c = keyCodes[String(ch)] { post(c, down: true); usleep(50_000); post(c, down: false); usleep(120_000) } }
default: print("uso: keys.swift cmdtab <n> | combo ctrl+alt+right | type texto"); exit(1)
}
