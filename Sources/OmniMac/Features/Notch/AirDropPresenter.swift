import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AirDrop y archivos arrastrados

/// Extrae las URLs de archivo de un arrastre y las entrega en el hilo principal.
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []

    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            }
            if let url {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
    }
    group.notify(queue: .main) {
        completion(urls)
    }
}

/// Abre la ventana de AirDrop del sistema con los archivos dados.
func sendViaAirDrop(_ urls: [URL]) {
    AirDropPresenter.shared.send(urls)
}

/// Presenta AirDrop desde nuestro panel. Dos detalles que antes fallaban: hay que
/// esperar a que termine la sesión de arrastre (llamar al servicio dentro del `onDrop`
/// no abre nada) y darle una ventana origen: sin ella, la app accesoria sin ventana
/// principal no tiene dónde anclar la hoja de AirDrop.
final class AirDropPresenter: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropPresenter()
    weak var sourceWindow: NSWindow?
    private var service: NSSharingService?

    func send(_ urls: [URL]) {
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else {
            Toast.show("No he podido leer esos archivos", symbol: "exclamationmark.triangle.fill")
            return
        }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            Toast.show("AirDrop no está disponible", symbol: "airplane.slash")
            return
        }
        self.service = service
        service.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.sourceWindow?.makeKeyAndOrderFront(nil)
            guard service.canPerform(withItems: files) else {
                Toast.show("AirDrop no puede enviar esos archivos", symbol: "airplane.slash")
                return
            }
            Toast.show(files.count == 1 ? "Abriendo AirDrop…" : "Abriendo AirDrop con \(files.count) archivos…", symbol: "airplane.departure")
            service.perform(withItems: files)
            // El Finder (origen del arrastre) vuelve a activarse al soltar: nos ponemos
            // delante otra vez para que el selector de AirDrop reciba el teclado.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Sin ventana origen: anclada al panel del notch, la hoja de AirDrop salía medio
    /// fuera de la pantalla; sin ella, macOS la centra como ventana propia.
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .item
        return nil
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        Toast.show("AirDrop: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Toast.show(items.count == 1 ? "Enviado por AirDrop" : "\(items.count) archivos enviados por AirDrop", symbol: "checkmark.circle.fill")
    }
}
