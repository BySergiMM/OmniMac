import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Compone el texto como lo hace cualquier campo de macOS: dejándoselo al sistema
/// de entrada.
///
/// Antes se leía `charactersIgnoringModifiers` y se pegaba a mano, y eso se salta
/// toda la maquinaria: en un teclado español la tecla muerta `´` no componía («´»
/// y luego «a» daban «a», nunca «á»), ⌥2 escribía «2» en vez de «@», y cualquier
/// método de entrada (japonés, chino) era imposible. La vista no pinta nada: solo
/// recibe las teclas y cuenta lo que el sistema compone.
final class QueryInputView: NSView, NSTextInputClient {
    var onInsert: ((String) -> Void)?
    /// Texto a medio componer (el subrayado de los métodos de entrada).
    var onMarkedText: ((String) -> Void)?

    private var marked = ""

    override var acceptsFirstResponder: Bool { true }

    private func text(from any: Any) -> String {
        (any as? NSAttributedString)?.string ?? (any as? String) ?? ""
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        if !marked.isEmpty { marked = ""; onMarkedText?("") }
        let inserted = text(from: string)
        guard !inserted.isEmpty else { return }
        onInsert?(inserted)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = text(from: string)
        onMarkedText?(marked)
    }

    func unmarkText() { marked = ""; onMarkedText?("") }
    func hasMarkedText() -> Bool { !marked.isEmpty }
    func markedRange() -> NSRange {
        marked.isEmpty ? NSRange(location: NSNotFound, length: 0)
                       : NSRange(location: 0, length: marked.utf16.count)
    }
    func selectedRange() -> NSRange { NSRange(location: marked.utf16.count, length: 0) }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    /// Dónde pinta el sistema la lista de candidatos: justo debajo de la línea de
    /// búsqueda, que está arriba del panel.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let inWindow = NSRect(x: 60, y: window.frame.height - 62, width: 1, height: 1)
        return window.convertToScreen(inWindow)
    }

    /// Intro, flechas y borrar los lleva el panel; aquí no se hace nada con ellos.
    override func doCommand(by selector: Selector) {}
}

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
/// entrega un `rootView` nuevo. Para ocho filas es gratis, y no hay nada mágico que
/// pueda fallar en silencio.
final class CommandBarPanelController: NSObject, NSWindowDelegate {
    var onRun: ((Command) -> Void)?

    /// Lo que caben en pantalla y lo que se enseña: el mismo número, para que la
    /// selección no pueda irse por debajo del borde.
    static let maxRows = 8

    private(set) var query = "" { didSet { applyFilter() } }
    private(set) var results: [Command] = []
    private(set) var selection = 0 { didSet { render() } }

    private var all: [Command] = []
    private var marked = "" { didSet { render() } }
    private var host: FirstClickHostingView<CommandBarView>?
    private var panel: KeyablePanel?
    private var input: QueryInputView?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    /// Si está puesto o no lo decidimos nosotros, no la ventana: `isVisible` sigue
    /// siendo `true` mientras se desvanece, y con eso el atajo se volvía un «una vez
    /// sí y otra no».
    private var shown = false
    /// El borde de arriba no se mueve aunque cambie el número de filas. Si no, la
    /// línea de búsqueda baila bajo los dedos según escribes y borras.
    private var topEdge: CGFloat = 0

    var isVisible: Bool { shown }

    func show(commands: [Command]) {
        previousApp = NSWorkspace.shared.frontmostApplication
        all = commands
        marked = ""
        query = ""
        selection = 0

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = FirstClickHostingView(rootView: makeView())
        self.host = host

        let input = self.input ?? makeInput()
        self.input = input
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 200))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(input)
        panel.contentView = container

        placeOnScreenUnderTheMouse()
        resize()
        shown = true
        // Sin `NSApp.activate`: activar una app accesoria deja la ventana en un
        // estado en el que SwiftUI deja de refrescarla. Se veía la primera lista y
        // ahí se quedaba, aunque el modelo sí cambiara al escribir.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)
        installKeyMonitor()
    }

    /// - Parameter returningFocus: devolver el foco a lo que estaba delante. Solo
    ///   cuando lo cierras tú (Escape, el atajo, Intro). Si se cierra porque has
    ///   pinchado en otra app, devolver el foco sería arrancarte de donde acabas de
    ///   ir.
    func hide(returningFocus: Bool = true) {
        guard shown else { return }
        shown = false
        removeKeyMonitor()
        panel?.orderOut(nil)
        if returningFocus, let previous = previousApp,
           previous.bundleIdentifier != Bundle.main.bundleIdentifier,
           !previous.isTerminated {
            previous.activate()
        }
        previousApp = nil
        marked = ""
    }

    func commit(_ index: Int) {
        guard results.indices.contains(index) else { return hide() }
        onRun?(results[index])
    }

    /// Las apps tardan en listarse, así que llegan después de abrir el panel.
    func add(_ extra: [Command]) {
        guard shown, !extra.isEmpty else { return }
        all += extra
        applyFilter()
    }

    // MARK: - La lista

    private func applyFilter() {
        // Sin nada escrito, solo los comandos de OmniMac: abrir el panel y que lo
        // primero que veas sean 300 apps no ayuda a nadie.
        let typed = query.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            // Sin nada escrito, las funciones de OmniMac en el orden en que están
            // escritas, que va de lo más usado a lo menos. Antes se ordenaban
            // alfabéticamente y se cortaban a ocho, así que seis no salían nunca.
            results = all.filter { !$0.id.hasPrefix("app:") }
        } else {
            // Una sola clasificación, con una ventaja pequeña para lo que hace
            // OmniMac. Antes se ordenaban por separado y las apps iban detrás
            // siempre: al escribir «mail» salía «Mantener el Mac despierto» con 12
            // puntos por delante de Mail con 37, y Mail caía al sexto puesto.
            results = CommandMatcher.rank(all, query: typed, limit: 12,
                                          bonus: { $0.id.hasPrefix("app:") ? 0 : 6 }) { $0.searchable }
        }
        selection = 0
        resize()
        render()
    }

    /// Le da a la vista el estado de ahora, y le exige que se pinte.
    ///
    /// Cambiar `rootView` no basta: como OmniMac vive en la barra de menús, la app
    /// no está activa, y AppKit no repinta sus ventanas hasta que llega otro evento.
    /// El efecto era el fallo más visible del buscador: escribías «safari», el
    /// modelo ya tenía un único resultado —Safari, con 85 puntos— y en pantalla
    /// seguía la fila anterior. Pulsar una flecha lo «arreglaba», porque forzaba el
    /// repintado.
    private func render() {
        guard let panel, let container = panel.contentView, let input else { return }
        let fresh = FirstClickHostingView(rootView: makeView())
        fresh.frame = container.bounds
        fresh.autoresizingMask = [.width, .height]
        host?.removeFromSuperview()
        container.addSubview(fresh, positioned: .below, relativeTo: input)
        host = fresh
    }

    private func makeView() -> CommandBarView {
        CommandBarView(query: query, marked: marked, results: results, selection: selection) { [weak self] index in
            self?.commit(index)
        }
    }

    private func makeInput() -> QueryInputView {
        let input = QueryInputView(frame: .zero)
        input.onInsert = { [weak self] text in self?.query += text }
        input.onMarkedText = { [weak self] text in self?.marked = text }
        return input
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
        panel.delegate = self
        return panel
    }

    /// La pantalla donde está el ratón, que es donde está mirando quien escribe.
    /// `NSScreen.main` es «la de la ventana con el teclado», y como la app vive en la
    /// barra de menús y no tiene ninguna, en dos pantallas salía siempre en la
    /// principal.
    private func placeOnScreenUnderTheMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let fullHeight = 62 + CGFloat(Self.maxRows) * 46 + 8
        topEdge = screen.visibleFrame.midY + fullHeight / 2 + 110
    }

    private func resize() {
        guard let panel else { return }
        if topEdge == 0 { placeOnScreenUnderTheMouse() }
        let width: CGFloat = 560
        let rows = min(Self.maxRows, results.count)
        let height: CGFloat = 62 + (rows == 0 ? (query.isEmpty ? 0 : 44) : CGFloat(rows) * 46 + 8)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: panel.frame.midX, y: topEdge - 1)) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let midX = (screen ?? NSScreen.screens[0]).visibleFrame.midX
        panel.setFrame(CGRect(x: midX - width / 2, y: topEdge - height, width: width, height: height),
                       display: true)
    }

    // MARK: - Teclado

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // `isKeyWindow` y no `isVisible`: si el panel sigue por ahí sin el
            // teclado, las teclas son de la ventana de Ajustes, no nuestras.
            guard let self, self.shown, self.panel?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

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
                // Sin repetición: con Intro pulsado, el comando se ejecutaba una vez
                // por repetición de tecla.
                guard !event.isARepeat else { return nil }
                self.commit(self.selection)
                return nil
            case Int(kVK_Delete) where !self.composing:
                if !self.query.isEmpty { self.query.removeLast() }
                return nil
            default:
                break
            }

            if flags.contains(.command) {
                // ⌘V pega en la búsqueda; el resto de combinaciones con ⌘ no son
                // nuestras, pero tampoco las ve nadie (la app no tiene menú), así
                // que se descartan sin ruido.
                if event.charactersIgnoringModifiers?.lowercased() == "v",
                   let text = NSPasteboard.general.string(forType: .string) {
                    self.query += text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }
            guard !flags.contains(.control) else { return nil }
            // El sistema de entrada compone: acentos, ⌥ y métodos de entrada.
            self.input?.interpretKeyEvents([event])
            return nil
        }
    }

    private var composing: Bool { input?.hasMarkedText() ?? false }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit { removeKeyMonitor() }
}

// MARK: - Cuando pierde el teclado

extension CommandBarPanelController {
    /// Si el panel deja de tener el teclado —un clic en otra app, en el escritorio,
    /// o el ⌘Tab de siempre— se cierra. Antes se quedaba flotando encima de todo y
    /// tragándose las teclas, y el siguiente ⌥Espacio lo cerraba en vez de abrirlo.
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        hide(returningFocus: false)
    }
}

// MARK: - Vista

struct CommandBarView: View {
    let query: String
    /// Lo que un método de entrada está componiendo todavía.
    var marked: String = ""
    let results: [Command]
    let selection: Int
    let onRun: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                if query.isEmpty && marked.isEmpty {
                    Text(L("Buscar una función o una app…", "Search a feature or an app…"))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(query) + Text(marked).underline()
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 19))
            .padding(.horizontal, 18)
            .frame(height: 60)

            if !results.isEmpty {
                Divider()
                // Con desplazamiento y siguiendo a la selección, como el panel del
                // portapapeles: caben ocho filas y puede haber doce resultados, así
                // que sin esto la marca se iba por debajo del borde y parecía que no
                // había nada seleccionado.
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                CommandRow(command: command, selected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onRun(index) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Al aparecer y no al cambiar: la vista se crea entera en cada
                    // pulsación, así que `onChange` no llega a dispararse nunca.
                    .onAppear { proxy.scrollTo(selection) }
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
