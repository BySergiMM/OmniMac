import AppKit
import UniformTypeIdentifiers

/// Diálogo del Finder para elegir archivos (varios a la vez).
enum FilePicker {
    static func choose(message: String, prompt: String, completion: @escaping ([URL]) -> Void) {
        open(message: message, prompt: prompt, types: nil, directory: nil, completion: completion)
    }

    /// El mismo diálogo, pero solo deja elegir apps y empieza en `/Applications`.
    ///
    /// Las listas de apps se guardan por identificador de paquete, y un archivo
    /// cualquiera no tiene ninguno: mejor no dejar elegirlo que aceptarlo y no hacer
    /// nada con él.
    static func chooseApps(message: String, prompt: String, completion: @escaping ([URL]) -> Void) {
        open(message: message, prompt: prompt, types: [.application],
             directory: URL(fileURLWithPath: "/Applications"), completion: completion)
    }

    private static func open(message: String, prompt: String, types: [UTType]?, directory: URL?,
                             completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.level = .modalPanel
        if let types { panel.allowedContentTypes = types }
        if let directory { panel.directoryURL = directory }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            completion(panel.urls)
        }
    }
}
