import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña bandeja + AirDrop

struct TrayTab: View {
    @ObservedObject var model: NotchModel

    private var shelfTargeted: Bool { model.dropZone == .shelf }

    var body: some View {
        HStack(spacing: 12) {
            shelfZone
            AirDropZone(model: model)
                .frame(width: 118)
        }
    }

    @ViewBuilder
    private var shelfZone: some View {
        Group {
            if model.shelf.isEmpty {
                Button {
                    FilePicker.choose(message: L("Elige los archivos que quieres tener a mano en el notch", "Choose the files you want to keep at hand in the notch"), prompt: L("Añadir", "Add")) { urls in
                        model.addToShelf(urls)
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(.white.opacity(shelfTargeted ? 0.6 : 0.22))
                        .overlay(
                            VStack(spacing: 5) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 17))
                                Text(L("Suelta archivos aquí o haz clic\npara elegirlos en el Finder", "Drop files here or click\nto choose them in Finder"))
                                    .font(.system(size: 10.5))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.white.opacity(shelfTargeted ? 0.9 : 0.45))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Suelta archivos o haz clic para elegirlos", "Drop files or click to choose them"))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.shelf, id: \.self) { url in
                            shelfItem(url)
                        }
                        Button {
                            FilePicker.choose(message: L("Elige los archivos que quieres tener a mano en el notch", "Choose the files you want to keep at hand in the notch"), prompt: L("Añadir", "Add")) { urls in
                                model.addToShelf(urls)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.white.opacity(0.12)))
                        }
                        .buttonStyle(PressScaleStyle())
                        .help(L("Añadir archivos desde el Finder", "Add files from Finder"))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(shelfTargeted ? 0.1 : 0.05))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shelfItem(_ url: URL) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 34, height: 34)
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 62)
        }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button(L("Abrir", "Open")) { NSWorkspace.shared.open(url) }
            Button(L("Mostrar en Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(L("Enviar por AirDrop", "Send by AirDrop")) { sendViaAirDrop([url]) }
            Divider()
            Button(L("Quitar de la bandeja", "Remove from tray")) { model.shelf.removeAll { $0 == url } }
            Button(L("Vaciar bandeja", "Empty tray")) { model.shelf.removeAll() }
        }
        .help(url.lastPathComponent)
    }
}

/// Zona azul: soltar archivos aquí abre AirDrop con ellos.
struct AirDropZone: View {
    @ObservedObject var model: NotchModel

    private var targeted: Bool { model.dropZone == .airdrop }

    var body: some View {
        Button {
            FilePicker.choose(message: L("Elige los archivos que quieres enviar por AirDrop", "Choose the files you want to send by AirDrop"), prompt: L("Enviar por AirDrop", "Send by AirDrop")) { urls in
                sendViaAirDrop(urls)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: NotchSymbols.airdrop)
                    .font(.system(size: 22, weight: .medium))
                Text("AirDrop")
                    .font(.system(size: 11, weight: .semibold))
                Text(L("suelta aquí o haz clic", "drop here or click"))
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundStyle(targeted ? .white : Color(red: 0.35, green: 0.65, blue: 1.0))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.2, green: 0.45, blue: 1.0).opacity(targeted ? 0.45 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0).opacity(targeted ? 0.9 : 0.4))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(L("Suelta archivos para enviarlos o haz clic para elegirlos", "Drop files to send them or click to choose them"))
        .background(
            // Publica su marco para que el destino único del notch sepa dónde está.
            GeometryReader { geo in
                Color.clear.preference(key: AirDropFrameKey.self, value: geo.frame(in: .named("notch")))
            }
        )
    }
}

struct AirDropFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Destino de arrastre único del notch: abre el notch en la bandeja al entrar,
/// resalta la zona sobre la que está el archivo y, al soltar, lo guarda en la
/// bandeja o lo envía por AirDrop según dónde caiga.
struct NotchDropDelegate: DropDelegate {
    let model: NotchModel
    let airDropFrame: () -> CGRect

    private func zone(for info: DropInfo) -> NotchDropZone {
        guard model.expanded, model.tab == .tray else { return .shelf }
        return airDropFrame().contains(info.location) ? .airdrop : .shelf
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        if model.enabledTabs.contains(.tray) { model.tab = .tray }
        model.onExpandRequest?()
        model.dropZone = zone(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let current = zone(for: info)
        if model.dropZone != current { model.dropZone = current }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        model.dropZone = .none
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(for: info)
        model.dropZone = .none
        let providers = info.itemProviders(for: [.fileURL])
        loadFileURLs(providers) { urls in
            if target == .airdrop {
                sendViaAirDrop(urls)
            } else {
                model.addToShelf(urls)
            }
        }
        return true
    }
}
