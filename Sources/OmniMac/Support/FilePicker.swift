import AppKit

/// Diálogo del Finder para elegir archivos (varios a la vez).
enum FilePicker {
    static func choose(message: String, prompt: String, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            completion(panel.urls)
        }
    }
}
