import AppKit
import Carbon.HIToolbox
import SwiftUI

/// El panel del buscador de comandos.
///
/// Mismo esqueleto que el del portapapeles: un `NSPanel` sin barra de título que sí
/// acepta teclado, con un vigilante de teclas mientras está delante.
/// El panel no usa `ObservableObject`.
///
/// Se intentó, y la vista se quedaba congelada en la primera lista aunque el modelo
/// sí cambiara al escribir: dentro de un `NSHostingView` metido en un `NSPanel` sin
/// barra de título, las notificaciones no llegaban a repintar. En vez de pelearse
/// con eso, la vista es **función pura del estado**: cuando cambia algo, se le
/// entrega un `rootView` nuevo. Para doce filas es gratis, y no hay nada mágico que
/// pueda fallar en silencio.
final class CommandBarPanelController {
    var onRun: ((Command) -> Void)?

    private(set) var query = "" { didSet { applyFilter() } }
    private(set) var results: [Command] = []
    private(set) var selection = 0 { didSet { render() } }

    private var all: [Command] = []
    private var host: FirstClickHostingView<CommandBarView>?
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(commands: [Command]) {
        previousApp = NSWorkspace.shared.frontmostApplication
        all = commands
        query = ""
        selection = 0

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = FirstClickHostingView(rootView: makeView())
        self.host = host
        panel.contentView = host
        resize()
        // Sin `NSApp.activate`: activar una app accesoria deja la ventana en un
        // estado en el que SwiftUI deja de refrescarla. Se veía la primera lista y
        // ahí se quedaba, aunque el modelo sí cambiara al escribir.
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        // Se devuelve el foco a lo que estuviera delante, para que el comando actúe
        // sobre ello y no sobre nosotros.
        previousApp?.activate()
        previousApp = nil
    }

    func commit(_ index: Int) {
        guard results.indices.contains(index) else { return hide() }
        onRun?(results[index])
    }

    private func applyFilter() {
        // Sin nada escrito, solo los comandos de OmniMac: abrir el panel y que lo
        // primero que veas sean 300 apps no ayuda a nadie.
        let base = query.isEmpty ? all.filter { !$0.id.hasPrefix("app:") } : all
        // Con el mismo encaje ganan los comandos de OmniMac: buscar «mic» tiene que
        // dar «Silenciar el micrófono» antes que «Mission Control». Para eso se
        // ordenan por separado y las apps van detrás.
        let own = base.filter { !$0.id.hasPrefix("app:") }
        let apps = base.filter { $0.id.hasPrefix("app:") }
        results = Array((CommandMatcher.rank(own, query: query, limit: 8) { $0.searchable }
                         + CommandMatcher.rank(apps, query: query, limit: 8) { $0.searchable }).prefix(12))
        selection = 0
        resize()
        render()
    }

    /// Le da a la vista el estado de ahora.
    private func render() {
        host?.rootView = makeView()
    }

    private func makeView() -> CommandBarView {
        CommandBarView(query: query, results: results, selection: selection) { [weak self] index in
            self?.commit(index)
        }
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .popUpMenu   // después de isFloatingPanel, que lo reinicia
        return panel
    }

    private func resize() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = 560
        let rows = min(8, results.count)
        let height: CGFloat = 62 + (rows == 0 ? 44 : CGFloat(rows) * 46 + 8)
        // Un poco por encima del centro: es donde el ojo lo espera.
        let frame = CGRect(x: screen.visibleFrame.midX - width / 2,
                           y: screen.visibleFrame.midY - height / 2 + 110,
                           width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    // MARK: - Teclado

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch Int(event.keyCode) {
            case Int(kVK_Escape):
                self.hide()
                return nil
            case Int(kVK_DownArrow):
                if self.selection < self.results.count - 1 { self.selection += 1 }
                return nil
            case Int(kVK_UpArrow):
                if self.selection > 0 { self.selection -= 1 }
                return nil
            case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
                self.commit(self.selection)
                return nil
            case Int(kVK_Delete):
                if !self.query.isEmpty { self.query.removeLast() }
                return nil
            default:
                // El texto se compone aquí y no en un `TextField`.
                //
                // Un `NSPanel` sin barra de título no le da el foco a un campo de
                // SwiftUI por mucho `@FocusState` que se le ponga: se ve el cursor
                // pero no llega ni una letra. Es el mismo camino que ya sigue el
                // panel del portapapeles, y funciona.
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // `charactersIgnoringModifiers` y no `characters`: el segundo llega
                // vacío cuando la app no está activa —que es siempre, porque OmniMac
                // vive en la barra de menús— y el buscador se quedaba mudo aunque
                // las flechas y Escape sí funcionaran.
                guard !flags.contains(.command), !flags.contains(.control),
                      let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                      characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                                                             && !CharacterSet.illegalCharacters.contains($0)
                                                             && $0.value < 0xF700 })
                else { return event }
                self.query += characters
                return nil
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit { removeKeyMonitor() }
}

// MARK: - Vista

struct CommandBarView: View {
    let query: String
    let results: [Command]
    let selection: Int
    let onRun: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                if query.isEmpty {
                    Text(L("Buscar una función o una app…", "Search a feature or an app…"))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(query)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 19))
            .padding(.horizontal, 18)
            .frame(height: 60)

            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                            CommandRow(command: command, selected: index == selection)
                                .contentShape(Rectangle())
                                .onTapGesture { onRun(index) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else if !query.isEmpty {
                Divider()
                Text(L("Nada que coincida", "Nothing matches"))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct CommandRow: View {
    let command: Command
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: command.symbol)
                .font(.system(size: 14))
                .frame(width: 22)
                .foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Text(command.subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
            }
            Spacer(minLength: 8)
            if selected {
                Text("↵").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(selected ? Brand.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
    }
}
