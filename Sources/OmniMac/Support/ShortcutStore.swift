import Combine
import Foundation

/// Qué atajo tiene cada acción ahora mismo, y cuáles no se han podido reservar.
///
/// Antes todos los atajos estaban escritos a fuego. El problema no era la falta de
/// personalización: era que `RegisterEventHotKey` falla si otra app ya tiene esa
/// combinación, **y nadie se enteraba**. Quien tuviera Rectangle instalado pulsaba
/// ⌃⌥→, no pasaba nada y no había ningún mensaje. La conclusión razonable era que
/// OmniMac estaba roto.
///
/// Aquí se guarda lo que el usuario haya cambiado y, sobre todo, **qué atajos se
/// quedaron sin registrar**, para que Ajustes lo pueda decir.
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// Claves de los atajos que no se pudieron reservar porque los tiene otra app.
    @Published private(set) var unavailable: Set<String> = []

    /// El catálogo de todo lo que se puede cambiar, en el orden en que se registró.
    /// Sirve para detectar choques entre dos acciones de la propia OmniMac.
    private(set) var catalogue: [ShortcutBinding] = []

    private let defaults: UserDefaults
    /// Lo que hay que volver a registrar cuando cambia un atajo: la acción original.
    private var rebinders: [String: () -> Void] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Leer y escribir

    private func storageKey(_ binding: ShortcutBinding) -> String { "shortcut.\(binding.key)" }

    /// El atajo que toca usar: el del usuario si lo hay, y si no el de fábrica.
    ///
    /// Un valor guardado vacío quiere decir «sin atajo»: el usuario lo quitó a
    /// propósito, normalmente porque lo quería para otra app.
    func shortcut(for binding: ShortcutBinding) -> Shortcut? {
        guard let stored = defaults.string(forKey: storageKey(binding)) else { return binding.fallback }
        if stored.isEmpty { return nil }
        return Shortcut(stored: stored) ?? binding.fallback
    }

    /// ¿Está en el valor de fábrica?
    func isDefault(_ binding: ShortcutBinding) -> Bool {
        defaults.string(forKey: storageKey(binding)) == nil
    }

    /// Cambia el atajo. `nil` lo deja sin atajo.
    func set(_ shortcut: Shortcut?, for binding: ShortcutBinding) {
        defaults.set(shortcut?.stored ?? "", forKey: storageKey(binding))
        applyChange(binding)
    }

    /// Vuelve al de fábrica.
    func reset(_ binding: ShortcutBinding) {
        defaults.removeObject(forKey: storageKey(binding))
        applyChange(binding)
    }

    private func applyChange(_ binding: ShortcutBinding) {
        objectWillChange.send()
        // Volver a registrar corre por cuenta del módulo dueño del atajo, que es
        // quien sabe qué hacer cuando se pulsa.
        rebinders[binding.key]?()
    }

    // MARK: - Catálogo y choques

    /// Lo llama `HotKeyCenter` cada vez que un módulo enlaza un atajo.
    func remember(_ binding: ShortcutBinding, rebind: @escaping () -> Void) {
        if !catalogue.contains(where: { $0.key == binding.key }) { catalogue.append(binding) }
        rebinders[binding.key] = rebind
    }

    func forget(_ binding: ShortcutBinding) {
        rebinders[binding.key] = nil
    }

    /// Otra acción **de OmniMac** que quiere la misma combinación.
    ///
    /// Esto es distinto de `unavailable`: aquí el choque es interno y se puede
    /// arreglar; allí lo tiene otra app y no podemos hacer nada.
    func conflict(for binding: ShortcutBinding) -> ShortcutBinding? {
        guard let mine = shortcut(for: binding) else { return nil }
        return catalogue.first { other in
            other.key != binding.key && shortcut(for: other) == mine
        }
    }

    // MARK: - Quién se quedó sin sitio

    func markUnavailable(_ binding: ShortcutBinding, _ failed: Bool) {
        let changed = failed ? unavailable.insert(binding.key).inserted
                             : unavailable.remove(binding.key) != nil
        if changed { objectWillChange.send() }
    }

    func isUnavailable(_ binding: ShortcutBinding) -> Bool { unavailable.contains(binding.key) }
}
