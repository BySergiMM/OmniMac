import AppKit
import SwiftUI

/// Panel del selector ⌘Tab: cuadrícula de ventanas con miniaturas, búsqueda al escribir y manejo por teclado.
final class SwitcherModel: ObservableObject {
    @Published var windows: [SwitcherWindow] = []
    @Published var selection = 0
    @Published var columns = 1
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    /// Texto escrito para filtrar (título de ventana o nombre de app).
    @Published var filter = ""
    var allWindows: [SwitcherWindow] = []
    var showThumbnails = true
    var itemSize = CGSize(width: 210, height: 168)
    let spacing: CGFloat = 8
    let padding: CGFloat = 16
    static let headerHeight: CGFloat = 30
}

/// Panel flotante del selector de ventanas. No activa la app ni roba el foco:
/// el teclado llega a través del event tap del módulo.
final class SwitcherPanelController {
    var onCommit: (() -> Void)?

    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var thumbnailTask: Task<Void, Never>?

    /// Captura las miniaturas en segundo plano y las va enseñando según llegan
    /// (el selector aparece al instante con iconos y las miniaturas los sustituyen).
    private func captureThumbnails(for windows: [SwitcherWindow]) {
        thumbnailTask?.cancel()
        let ids = Set(windows.map(\.id))
        let model = self.model
        thumbnailTask = Task {
            let images = await WindowThumbnails.capture(windowIDs: ids)
            if Task.isCancelled { return }
            await MainActor.run { model.thumbnails = images }
        }
    }

    var selectedWindow: SwitcherWindow? {
        guard model.windows.indices.contains(model.selection) else { return nil }
        return model.windows[model.selection]
    }

    var isEmpty: Bool { model.allWindows.isEmpty }

    func show(windows: [SwitcherWindow], initialSelection: Int, thumbnails: Bool) {
        model.allWindows = windows
        model.windows = windows
        model.filter = ""
        model.selection = max(0, min(initialSelection, windows.count - 1))
        model.showThumbnails = thumbnails
        model.thumbnails = [:]
        // Con miniaturas las celdas son más anchas (como AltTab); sin ellas, compactas.
        model.itemSize = thumbnails ? CGSize(width: 210, height: 168) : CGSize(width: 152, height: 132)

        if thumbnails {
            captureThumbnails(for: windows)
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = SwitcherView(model: model, onClick: { [weak self] index in
            self?.model.selection = index
            self?.onCommit?()
        })
        panel.contentView = FirstClickHostingView(rootView: view)
        relayout()
        panel.orderFrontRegardless()
    }

    func hide() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        panel?.orderOut(nil)
    }

    func advance(_ delta: Int) {
        let count = model.windows.count
        guard count > 0 else { return }
        model.selection = ((model.selection + delta) % count + count) % count
    }

    func advanceRow(_ delta: Int) {
        let count = model.windows.count
        guard count > 0 else { return }
        let target = model.selection + delta * model.columns
        if (0..<count).contains(target) {
            model.selection = target
        }
    }

    // MARK: - Búsqueda

    func filterAppend(_ text: String) {
        model.filter += text
        applyFilter()
    }

    func filterBackspace() {
        guard !model.filter.isEmpty else { return }
        model.filter.removeLast()
        applyFilter()
    }

    private func applyFilter(keepSelection: Bool = false) {
        let query = model.filter.trimmingCharacters(in: .whitespaces).lowercased()
        let previous = selectedWindow?.id
        if query.isEmpty {
            model.windows = model.allWindows
        } else {
            model.windows = model.allWindows.filter {
                $0.title.lowercased().contains(query) || $0.appName.lowercased().contains(query)
            }
        }
        if keepSelection, let previous, let index = model.windows.firstIndex(where: { $0.id == previous }) {
            model.selection = index
        } else {
            model.selection = max(0, min(model.selection, model.windows.count - 1))
            if !keepSelection { model.selection = 0 }
        }
        relayout()
    }

    // MARK: - Acciones sobre la ventana elegida

    func closeSelected() {
        guard let window = selectedWindow else { return }
        if let button = AX.element(window.axElement, kAXCloseButtonAttribute as String) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
        remove([window.id])
    }

    func minimizeSelected() {
        guard let window = selectedWindow else { return }
        AX.set(window.axElement, kAXMinimizedAttribute as String, to: kCFBooleanTrue)
        remove([window.id])
    }

    func hideSelectedApp() {
        guard let window = selectedWindow else { return }
        NSRunningApplication(processIdentifier: window.pid)?.hide()
        remove(model.allWindows.filter { $0.pid == window.pid }.map(\.id))
    }

    func quitSelectedApp() {
        guard let window = selectedWindow else { return }
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
        remove(model.allWindows.filter { $0.pid == window.pid }.map(\.id))
    }

    private func remove(_ ids: [CGWindowID]) {
        let gone = Set(ids)
        model.allWindows.removeAll { gone.contains($0.id) }
        applyFilter(keepSelection: true)
    }

    // MARK: - Ventana

    private func relayout() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let count = max(1, model.windows.count)
        let usableWidth = screen.visibleFrame.width * 0.85 - model.padding * 2 + model.spacing
        let maxColumns = max(1, Int(usableWidth / (model.itemSize.width + model.spacing)))
        let columns = min(count, maxColumns)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let visibleRows = min(rows, 4)
        model.columns = columns

        let width = max(420, CGFloat(columns) * model.itemSize.width + CGFloat(columns - 1) * model.spacing + model.padding * 2)
        let height = SwitcherModel.headerHeight + 4
            + CGFloat(visibleRows) * model.itemSize.height + CGFloat(visibleRows - 1) * model.spacing + model.padding
        let frame = CGRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.midY - height / 2,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Después de `isFloatingPanel` (que lo reinicia a "flotante"): por encima de
        // la barra de menús y de las apps a pantalla completa.
        panel.level = .popUpMenu
        return panel
    }
}

// MARK: - Vistas

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onClick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: SwitcherModel.headerHeight)

            if model.windows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(L("Ninguna ventana coincide con «\(model.filter)»", "No window matches “\(model.filter)”"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.itemSize.width), spacing: model.spacing),
                                                 count: max(1, model.columns)),
                                  spacing: model.spacing) {
                            ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                                SwitcherItem(window: window,
                                             thumbnail: model.showThumbnails ? model.thumbnails[window.id] : nil,
                                             showThumbnails: model.showThumbnails,
                                             isSelected: index == model.selection,
                                             size: model.itemSize)
                                    .id(index)
                                    .onTapGesture { onClick(index) }
                                    .onHover { hovering in
                                        if hovering { model.selection = index }
                                    }
                            }
                        }
                        .padding(.horizontal, model.padding)
                        .padding(.top, 4)
                        .padding(.bottom, model.padding)
                    }
                    .onChange(of: model.selection) { _, newValue in
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.filter.isEmpty ? .tertiary : .secondary)
            if model.filter.isEmpty {
                Text(L("Escribe para buscar · ⌘W cerrar · ⌘M minimizar · ⌘H ocultar app · ⌘Q salir", "Type to search · ⌘W close · ⌘M minimize · ⌘H hide app · ⌘Q quit"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text(model.filter)
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct SwitcherItem: View {
    let window: SwitcherWindow
    var thumbnail: NSImage? = nil
    var showThumbnails: Bool = false
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        VStack(spacing: 6) {
            if showThumbnails {
                thumbnailView
            } else {
                iconView.frame(width: 60, height: 60)
            }

            VStack(spacing: 2) {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(showThumbnails ? 1 : 2)
                    .multilineTextAlignment(.center)
                Text(window.appName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.18) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Miniatura en vivo con el icono de la app como insignia (estilo AltTab).
    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // aún capturando (o sin permiso): fondo + icono grande
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.primary.opacity(0.06))
                        iconView.frame(width: 46, height: 46).opacity(0.9)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )

            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(4)
            }

            if window.isMinimized {
                Image(systemName: "arrow.down.forward.square.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private var iconView: some View {
        Group {
            if let icon = window.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
    }
}
