import AppKit
import Foundation

/// Idioma de la interfaz: por defecto el del Mac (español o inglés); se puede forzar en
/// Ajustes. Se fija al arrancar: cambiarlo reinicia la app.
enum AppLanguage: String, CaseIterable {
    case automatic = "auto"
    case spanish = "es"
    case english = "en"

    var title: String {
        switch self {
        case .automatic: L("Automático (el del Mac)", "Automatic (Mac language)")
        case .spanish: "Español"
        case .english: "English"
        }
    }
}

enum Localization {
    static let key = "app.language"

    static var preference: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .automatic
    }

    /// Guarda la preferencia y reinicia OmniMac para aplicarla.
    static func setPreference(_ language: AppLanguage) {
        guard language != preference else { return }
        UserDefaults.standard.set(language.rawValue, forKey: key)
        relaunch()
    }

    /// Idioma efectivo. Orden: variable OMNIMAC_LANG (tests), `--lang` (capturas),
    /// preferencia de Ajustes, idioma del sistema.
    static let isSpanish: Bool = {
        if let forced = ProcessInfo.processInfo.environment["OMNIMAC_LANG"] { return forced.lowercased().hasPrefix("es") }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--lang"), i + 1 < args.count { return args[i + 1].lowercased().hasPrefix("es") }
        switch preference {
        case .spanish: return true
        case .english: return false
        case .automatic: break
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("es")
    }()

    static var code: String { isSpanish ? "es" : "en" }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Texto en el idioma de la interfaz: `L("Guardar", "Save")`.
@inline(__always) func L(_ spanish: String, _ english: String) -> String {
    Localization.isSpanish ? spanish : english
}
