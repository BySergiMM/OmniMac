import AppKit
import Combine

/// Clase base de todos los módulos de OmniMac.
/// Persiste `isEnabled` en UserDefaults y arranca/detiene el módulo al cambiarlo.
class BaseFeature: NSObject, ObservableObject, Identifiable {
    let featureID: String
    let displayName: String
    let symbol: String
    let blurb: String

    var id: String { featureID }

    /// Los módulos que dependen del permiso de Accesibilidad lo indican aquí.
    var needsAccessibility: Bool { false }

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: "feature.\(featureID).enabled")
            if isEnabled { start() } else { stop() }
        }
    }

    init(id: String, name: String, symbol: String, blurb: String, defaultEnabled: Bool = true) {
        self.featureID = id
        self.displayName = name
        self.symbol = symbol
        self.blurb = blurb
        let key = "feature.\(id).enabled"
        if UserDefaults.standard.object(forKey: key) == nil {
            self.isEnabled = defaultEnabled
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: key)
        }
        super.init()
    }

    /// Arranca el módulo (se llama al activarse y al lanzar la app si está activado).
    func start() {}

    /// Detiene el módulo y libera recursos.
    func stop() {}
}
