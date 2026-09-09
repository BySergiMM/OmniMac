import AppKit
import Carbon.HIToolbox

/// Utilidades pequeñas y muy útiles que macOS no trae: copiar el texto de cualquier
/// zona de la pantalla (OCR), silenciar el micrófono con un atajo, bloquear el
/// teclado para limpiarlo y ocultar los iconos del escritorio.
final class ToolsFeature: BaseFeature {
    @Published private(set) var microphoneMuted = false
    @Published private(set) var desktopIconsHidden = DesktopIcons.hidden
    @Published private(set) var keyboardLocked = false

    /// ⌘Q solo cierra la app si se mantiene pulsado medio segundo.
    /// Velo negro por encima de todo, para bajar del mínimo de macOS.
    /// Arranca siempre a 0 a propósito: dejar la pantalla oscura al encender el
    /// Mac, sin que nadie sepa por qué, sería un mal recuerdo.
    @Published var dimLevel: Double = 0 {
        didSet {
            UserDefaults.standard.set(dimLevel, forKey: "tools.dimLevel")
            dimmer.apply(dimLevel)
        }
    }

    @Published var quitGuardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quitGuardEnabled, forKey: "tools.quitGuard")
            guard isEnabled else { return }
            if quitGuardEnabled { quitGuard.start() } else { quitGuard.stop() }
        }
    }

    /// Los atajos del módulo. Se pueden cambiar en Ajustes; estos son los de fábrica.
    static let shortcuts: [ShortcutBinding] = [
        ShortcutBinding(key: "tools.ocr", hotKeyID: 300,
                        title: L("Copiar texto de la pantalla", "Copy text from the screen"),
                        fallback: Shortcut(kVK_ANSI_2, cmdKey | shiftKey)),
        ShortcutBinding(key: "tools.mic", hotKeyID: 301,
                        title: L("Silenciar o activar el micrófono", "Mute or unmute the microphone"),
                        fallback: Shortcut(kVK_ANSI_M, controlKey | optionKey | cmdKey)),
        ShortcutBinding(key: "tools.lock", hotKeyID: 302,
                        title: L("Bloquear el teclado 30 segundos", "Lock the keyboard for 30 seconds"),
                        fallback: Shortcut(kVK_ANSI_L, controlKey | optionKey | cmdKey)),
        ShortcutBinding(key: "tools.color", hotKeyID: 303,
                        title: L("Copiar un color de la pantalla", "Copy a colour from the screen"),
                        fallback: Shortcut(kVK_ANSI_6, cmdKey | shiftKey)),
        ShortcutBinding(key: "tools.dimDown", hotKeyID: 620,
                        title: L("Bajar el brillo por debajo del mínimo", "Dim below the minimum"),
                        fallback: Shortcut(kVK_ANSI_Minus, controlKey | optionKey | cmdKey)),
        ShortcutBinding(key: "tools.dimUp", hotKeyID: 621,
                        title: L("Volver al brillo normal", "Back to normal brightness"),
                        fallback: Shortcut(kVK_ANSI_Equal, controlKey | optionKey | cmdKey)),
    ]

    private static var ocrShortcut: ShortcutBinding { shortcuts[0] }
    private static var micShortcut: ShortcutBinding { shortcuts[1] }
    private static var lockShortcut: ShortcutBinding { shortcuts[2] }
    private static var colorShortcut: ShortcutBinding { shortcuts[3] }
    private static var dimDownShortcut: ShortcutBinding { shortcuts[4] }
    private static var dimUpShortcut: ShortcutBinding { shortcuts[5] }
    private let ocr = ScreenTextCapture()
    private let keyboardLock = KeyboardLock()
    private let colorPicker = ScreenColorPicker()
    private let dimmer = ScreenDimmer()
    private let quitGuard = QuitGuard()

    init() {
        quitGuardEnabled = UserDefaults.standard.object(forKey: "tools.quitGuard") == nil ? true : UserDefaults.standard.bool(forKey: "tools.quitGuard")
        super.init(id: "tools",
                   name: L("Utilidades", "Tools"),
                   symbol: "wrench.and.screwdriver.fill",
                   blurb: L("Copiar texto de la pantalla, silenciar el micrófono, bloquear el teclado para limpiarlo y ocultar los iconos del escritorio.", "Copy text from the screen, mute the microphone, lock the keyboard to clean it and hide desktop icons."),
                   defaultEnabled: true)
        microphoneMuted = MicrophoneMute.isMuted
    }

    override func start() {
        HotKeyCenter.shared.bind(Self.ocrShortcut) { [weak self] in self?.captureText() }
        HotKeyCenter.shared.bind(Self.micShortcut) { [weak self] in self?.toggleMicrophone() }
        HotKeyCenter.shared.bind(Self.lockShortcut) { [weak self] in self?.lockKeyboard() }
        HotKeyCenter.shared.bind(Self.colorShortcut) { [weak self] in self?.pickColor() }
        HotKeyCenter.shared.bind(Self.dimDownShortcut) { [weak self] in self?.stepDim(+0.1) }
        HotKeyCenter.shared.bind(Self.dimUpShortcut) { [weak self] in self?.stepDim(-0.1) }
        if quitGuardEnabled { quitGuard.start() }
    }

    /// Un escalón de velo. En positivo oscurece, en negativo aclara.
    func stepDim(_ delta: Double) {
        let next = min(ScreenDimmer.maxLevel, max(0, dimLevel + delta))
        guard next != dimLevel else { return }
        dimLevel = next
        Toast.show(next < 0.001 ? L("Brillo normal", "Normal brightness")
                                : L("Brillo −\(Int(next * 100)) %", "Brightness −\(Int(next * 100))%"),
                   symbol: next < 0.001 ? "sun.max.fill" : "sun.min.fill")
    }

    func pickColor() {
        colorPicker.begin()
    }

    override func stop() {
        dimLevel = 0
        for binding in Self.shortcuts { HotKeyCenter.shared.unbind(binding) }
        keyboardLock.unlock()
        quitGuard.stop()
    }

    func captureText() {
        ocr.begin()
    }

    func toggleMicrophone() {
        let muted = MicrophoneMute.set(muted: !MicrophoneMute.isMuted)
        microphoneMuted = muted
        Toast.show(muted ? L("Micrófono silenciado", "Microphone muted") : L("Micrófono activado", "Microphone on"),
                   symbol: muted ? "mic.slash.fill" : "mic.fill")
    }

    func lockKeyboard() {
        guard !keyboardLocked else { return }
        keyboardLocked = true
        keyboardLock.lock(seconds: 30) { [weak self] in
            self?.keyboardLocked = false
        }
    }

    func toggleDesktopIcons() {
        DesktopIcons.setHidden(!DesktopIcons.hidden)
        desktopIconsHidden = DesktopIcons.hidden
        Toast.show(desktopIconsHidden ? L("Iconos del escritorio ocultos", "Desktop icons hidden") : L("Iconos del escritorio visibles", "Desktop icons visible"),
                   symbol: desktopIconsHidden ? "eye.slash" : "eye")
    }
}

// MARK: - Iconos del escritorio

/// Finder deja de dibujar los iconos del escritorio con `CreateDesktop = false`;
/// se reinicia solo (launchd lo vuelve a abrir) para aplicar el cambio.
enum DesktopIcons {
    private static let domain = "com.apple.finder" as CFString
    private static let key = "CreateDesktop" as CFString

    static var hidden: Bool {
        guard let value = CFPreferencesCopyAppValue(key, domain) else { return false }
        if let bool = value as? Bool { return !bool }
        if let string = value as? String { return ["false", "0", "no"].contains(string.lowercased()) }
        if let number = value as? NSNumber { return !number.boolValue }
        return false
    }

    static func setHidden(_ hidden: Bool) {
        CFPreferencesSetAppValue(key, (hidden ? kCFBooleanFalse : kCFBooleanTrue), domain)
        CFPreferencesAppSynchronize(domain)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.terminate()
    }
}
