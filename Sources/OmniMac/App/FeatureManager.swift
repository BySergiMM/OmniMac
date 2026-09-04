import AppKit
import Combine

/// Contenedor de todos los módulos de la app.
final class FeatureManager: ObservableObject {
    static let shared = FeatureManager()

    let keepAwake: KeepAwakeFeature
    let switcher: WindowSwitcherFeature
    let notch: NotchFeature
    let snapping: SnappingFeature
    let clipboard: ClipboardFeature
    let tools: ToolsFeature
    let sound: SoundFeature

    let all: [BaseFeature]

    private init() {
        let keepAwake = KeepAwakeFeature()
        self.keepAwake = keepAwake
        switcher = WindowSwitcherFeature()
        let sound = SoundFeature()
        self.sound = sound
        notch = NotchFeature(keepAwake: keepAwake, sound: sound)
        snapping = SnappingFeature()
        clipboard = ClipboardFeature()
        tools = ToolsFeature()
        all = [keepAwake, switcher, notch, snapping, clipboard, tools, sound]
    }

    func startEnabled() {
        for feature in all where feature.isEnabled {
            feature.start()
        }
    }

    /// Se llama cuando el usuario acaba de conceder Accesibilidad:
    /// reintenta arrancar lo que no pudo instalarse antes.
    func accessibilityGranted() {
        switcher.retryStartIfNeeded()
    }
}
