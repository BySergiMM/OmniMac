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
    @Published var quitGuardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quitGuardEnabled, forKey: "tools.quitGuard")
            guard isEnabled else { return }
            if quitGuardEnabled { quitGuard.start() } else { quitGuard.stop() }
        }
    }

    static let shortcutHelp: [(shortcut: String, action: String)] = [
        ("⇧⌘ 2", "Copiar texto de la pantalla: selecciona una zona y el texto va al portapapeles"),
        ("⌃⌥⌘ M", "Silenciar o activar el micrófono"),
        ("⌃⌥⌘ L", "Bloquear el teclado 30 segundos para limpiarlo"),
        ("⇧⌘ 6", "Copiar el color de un punto de la pantalla (en hexadecimal)"),
        ("⌘ Q mantenido", "Cerrar la app solo si mantienes ⌘Q medio segundo (evita cierres por accidente)"),
    ]

    private static let ocrHotKey: UInt32 = 300
    private static let micHotKey: UInt32 = 301
    private static let lockHotKey: UInt32 = 302
    private static let colorHotKey: UInt32 = 303
    private let ocr = ScreenTextCapture()
    private let keyboardLock = KeyboardLock()
    private let colorPicker = ScreenColorPicker()
    private let quitGuard = QuitGuard()

    init() {
        quitGuardEnabled = UserDefaults.standard.object(forKey: "tools.quitGuard") == nil ? true : UserDefaults.standard.bool(forKey: "tools.quitGuard")
        super.init(id: "tools",
                   name: "Utilidades",
                   symbol: "wrench.and.screwdriver.fill",
                   blurb: "Copiar texto de la pantalla, silenciar el micrófono, bloquear el teclado para limpiarlo y ocultar los iconos del escritorio.",
                   defaultEnabled: true)
        microphoneMuted = MicrophoneMute.isMuted
    }

    override func start() {
        HotKeyCenter.shared.register(id: Self.ocrHotKey,
                                     keyCode: UInt32(kVK_ANSI_2),
                                     modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.captureText()
        }
        HotKeyCenter.shared.register(id: Self.micHotKey,
                                     keyCode: UInt32(kVK_ANSI_M),
                                     modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.toggleMicrophone()
        }
        HotKeyCenter.shared.register(id: Self.lockHotKey,
                                     keyCode: UInt32(kVK_ANSI_L),
                                     modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.lockKeyboard()
        }
        HotKeyCenter.shared.register(id: Self.colorHotKey,
                                     keyCode: UInt32(kVK_ANSI_6),
                                     modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.pickColor()
        }
        if quitGuardEnabled { quitGuard.start() }
    }

    func pickColor() {
        colorPicker.begin()
    }

    override func stop() {
        HotKeyCenter.shared.unregister(id: Self.ocrHotKey)
        HotKeyCenter.shared.unregister(id: Self.micHotKey)
        HotKeyCenter.shared.unregister(id: Self.lockHotKey)
        HotKeyCenter.shared.unregister(id: Self.colorHotKey)
        keyboardLock.unlock()
        quitGuard.stop()
    }

    func captureText() {
        ocr.begin()
    }

    func toggleMicrophone() {
        let muted = MicrophoneMute.set(muted: !MicrophoneMute.isMuted)
        microphoneMuted = muted
        Toast.show(muted ? "Micrófono silenciado" : "Micrófono activado",
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
        Toast.show(desktopIconsHidden ? "Iconos del escritorio ocultos" : "Iconos del escritorio visibles",
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
