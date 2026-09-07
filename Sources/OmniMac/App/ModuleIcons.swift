import AppKit
import Combine

/// Qué módulos tienen icono propio en la barra de menús.
///
/// El icono general de OmniMac lleva a todo, pero por cada paso de más hay que
/// abrir el menú. Con esto se saca a la barra el módulo que uses a diario y se llega
/// a sus acciones con un clic.
///
/// Es opcional módulo a módulo, y de fábrica no hay ninguno: ocho iconos de la misma
/// app llenarían la barra, que es justo el problema que resuelve el escondedor de
/// iconos. Que elija cada uno.
final class ModuleIcons: ObservableObject {
    static let shared = ModuleIcons()

    /// Módulos que pueden tener icono propio, en el orden en que se enseñan.
    static let available: [String] = ["keepawake", "clipboard", "tools", "sound", "snapping"]

    @Published private(set) var enabled: Set<String>

    private init() {
        var stored: Set<String> = []
        for id in Self.available where UserDefaults.standard.bool(forKey: Self.key(id)) {
            stored.insert(id)
        }
        enabled = stored
    }

    static func key(_ moduleID: String) -> String { "feature.\(moduleID).menuBarIcon" }

    func isEnabled(_ moduleID: String) -> Bool { enabled.contains(moduleID) }

    func set(_ moduleID: String, enabled on: Bool) {
        guard Self.available.contains(moduleID) else { return }
        UserDefaults.standard.set(on, forKey: Self.key(moduleID))
        if on { enabled.insert(moduleID) } else { enabled.remove(moduleID) }
    }

    /// Sitio en la barra, a la derecha de la flecha del escondedor para que no se los
    /// trague (ver `MenuBarFeature`). Cuanto menor el número, más a la derecha.
    static func position(_ moduleID: String) -> Int {
        320 - (available.firstIndex(of: moduleID) ?? 0) * 2
    }
}
