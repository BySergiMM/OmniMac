import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Qué significa cada tecla dentro del panel del portapapeles.
///
/// La decisión va aparte del monitor de teclado para poder probarla sin abrir
/// ninguna ventana: aquí es donde se decide, por ejemplo, que un número suelto
/// **escribe en el buscador** y que para elegir por número hace falta ⌘.
enum PanelKey: Equatable {
    case close
    case clearQuery
    case moveUp
    case moveDown
    case paste
    case pin
    case deleteItem
    /// Borrar el último carácter del buscador.
    case backspace
    /// Elegir directamente el elemento número `n` (⌘1–⌘9).
    case pick(Int)
    /// Escribir en el buscador.
    case type(String)
    /// No es nuestra: que siga su camino.
    case passThrough

    static func action(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?,
                       queryIsEmpty: Bool, itemCount: Int) -> PanelKey {
        switch keyCode {
        case Int(kVK_Escape):
            // Con algo escrito, Esc limpia la búsqueda antes de cerrar el panel.
            return queryIsEmpty ? .close : .clearQuery
        case Int(kVK_DownArrow): return .moveDown
        case Int(kVK_UpArrow): return .moveUp
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter): return .paste
        case Int(kVK_ANSI_P) where flags.contains(.option): return .pin
        case Int(kVK_Delete): return flags.contains(.option) ? .deleteItem : .backspace
        default: break
        }
        guard let characters, !characters.isEmpty else { return .passThrough }
        // ⌘1–⌘9 elige directamente, y también mientras buscas.
        //
        // Antes bastaba el número suelto y no había forma de buscar nada que
        // empezara por una cifra: teclear «2026» pegaba el segundo elemento del
        // historial. El buscador manda; para elegir por número, ⌘.
        if flags.contains(.command), let digit = Int(characters), (1...9).contains(digit) {
            return digit <= itemCount ? .pick(digit - 1) : .passThrough
        }
        guard !flags.contains(.command), !flags.contains(.control) else { return .passThrough }
        let printable = characters.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        return printable ? .type(characters) : .passThrough
    }
}

/// Quién manda sobre la fila elegida del panel, el teclado o el ratón.
///
/// Al desplazarse la lista, las filas pasan por debajo de un puntero que nadie ha
/// movido y SwiftUI llama a `onHover` igual que si lo hubieras movido tú. Sin
/// distinguirlo, pulsar ↓ mueve la lista, la lista dispara el `onHover` de la fila
/// que cae bajo el puntero, esa fila pasa a estar elegida y vuelve a desplazarse:
/// el panel da saltos y acabas pegando lo que no era.
enum PanelSelection {
    /// El ratón solo manda si se ha movido de verdad desde la última vez que eligió
    /// el teclado. `nil` en el ancla significa que ya manda el ratón.
    static func hoverWins(anchor: NSPoint?, mouse: NSPoint) -> Bool {
        guard let anchor else { return true }
        return anchor != mouse
    }
}

/// Panel sin barra de título que sí puede recibir el teclado.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ClipboardPanelController: ObservableObject {
    var onSelect: ((ClipItem) -> Void)?

    /// Elementos visibles (filtrados por `query`).
    @Published var items: [ClipItem] = []
    @Published var selection = 0
    @Published var query = ""

    private var allItems: [ClipItem] = []
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// Dónde estaba el ratón cuando el teclado eligió fila (ver `PanelSelection`).
    private var mouseAnchor: NSPoint?
    /// La fila la eligió el teclado: hay que traerla a la vista. Con el ratón ya está.
    private(set) var selectionFromKeyboard = true

    /// Elegir con el teclado: se ancla el ratón para que la lista al desplazarse no
    /// le robe la fila.
    func selectWithKeyboard(_ index: Int) {
        selectionFromKeyboard = true
        mouseAnchor = NSEvent.mouseLocation
        selection = index
    }

    /// El puntero ha pasado por una fila: solo cuenta si se ha movido de verdad.
    func hover(_ index: Int) {
        guard PanelSelection.hoverWins(anchor: mouseAnchor, mouse: NSEvent.mouseLocation) else { return }
        mouseAnchor = nil
        selectionFromKeyboard = false
        selection = index
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [ClipItem]) {
        allItems = items
        query = ""
        self.items = items
        selectWithKeyboard(0)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = FirstClickHostingView(rootView: ClipboardListView(controller: self))
        resize()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        // Al pulsar en otra app el panel dejaba de recibir teclas —el monitor es
        // local— pero seguía flotando a nivel de menú por encima de todo, y de ahí no
        // lo sacaba ni Esc. Si pierde el foco, se va.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                self?.hide()
            }
    }

    func hide() {
        removeKeyMonitor()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel?.orderOut(nil)
    }

    func commit(_ index: Int) {
        guard items.indices.contains(index) else {
            hide()
            return
        }
        onSelect?(items[index])
    }

    // MARK: - Búsqueda

    private func applyFilter() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        items = needle.isEmpty ? allItems : allItems.filter { $0.text.lowercased().contains(needle) }
        selectWithKeyboard(0)
        resize()
    }

    private func resize() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = 480
        let height: CGFloat = items.isEmpty ? 200 : min(560, CGFloat(items.count) * 58 + 74)
        let frame = CGRect(x: screen.visibleFrame.midX - width / 2,
                           y: screen.visibleFrame.midY - height / 2 + 60,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
    }

    // MARK: - Teclado

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let action = PanelKey.action(keyCode: Int(event.keyCode),
                                         flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                                         characters: event.charactersIgnoringModifiers,
                                         queryIsEmpty: self.query.isEmpty,
                                         itemCount: self.items.count)
            return self.perform(action) ? nil : event
        }
    }

    /// Ejecuta la acción. Devuelve `false` si la tecla no era nuestra.
    private func perform(_ action: PanelKey) -> Bool {
        switch action {
        case .passThrough:
            return false
        case .close:
            hide()
        case .clearQuery:
            query = ""
            applyFilter()
        case .moveDown:
            if selection < items.count - 1 { selectWithKeyboard(selection + 1) }
        case .moveUp:
            if selection > 0 { selectWithKeyboard(selection - 1) }
        case .paste:
            commit(selection)
        case .pick(let index):
            commit(index)
        case .pin:
            if items.indices.contains(selection) { onPin?(items[selection]) }
        case .deleteItem:
            if items.indices.contains(selection) {
                let item = items[selection]
                onDelete?(item)
                allItems.removeAll { $0.id == item.id }
                applyFilter()
            }
        case .backspace:
            if !query.isEmpty {
                query.removeLast()
                applyFilter()
            }
        case .type(let characters):
            query += characters
            applyFilter()
        }
        return true
    }

    /// ⌥⌫ borra el elemento seleccionado del historial.
    var onDelete: ((ClipItem) -> Void)?
    /// ⌥P ancla o desancla el elemento seleccionado.
    var onPin: ((ClipItem) -> Void)?

    /// El módulo cambió la lista (anclar, etc.): refrescar manteniendo búsqueda y selección.
    func update(items: [ClipItem]) {
        let selectedID = self.items.indices.contains(selection) ? self.items[selection].id : nil
        allItems = items
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        self.items = needle.isEmpty ? allItems : allItems.filter { $0.text.lowercased().contains(needle) }
        if let selectedID, let index = self.items.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = max(0, min(selection, self.items.count - 1))
        }
        resize()
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .popUpMenu // después de isFloatingPanel, que lo reinicia
        return panel
    }
}

// MARK: - Vistas

struct ClipboardListView: View {
    @ObservedObject var controller: ClipboardPanelController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(controller.query.isEmpty ? .tertiary : .secondary)
                if controller.query.isEmpty {
                    Text(L("Escribe para buscar…", "Type to search…"))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(controller.query)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                Text(L("↑↓ o ⌘1–9 elegir · ↩ pegar · ⌥P anclar · ⌥⌫ borrar", "↑↓ or ⌘1–9 select · ↩ paste · ⌥P pin · ⌥⌫ delete"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            if controller.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: controller.query.isEmpty ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(controller.query.isEmpty ? L("Aún no hay nada copiado", "Nothing copied yet") : L("Nada coincide con «\(controller.query)»", "Nothing matches “\(controller.query)”"))
                        .foregroundStyle(.secondary)
                    if controller.query.isEmpty {
                        Text(L("Copia algo con ⌘C y aparecerá aquí", "Copy something with ⌘C and it will appear here"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(item: item,
                                             index: index,
                                             showIndex: true,
                                             isSelected: index == controller.selection)
                                    .id(index)
                                    .onTapGesture { controller.commit(index) }
                                    .onHover { hovering in
                                        if hovering { controller.hover(index) }
                                    }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: controller.selection) { _, newValue in
                        // Con el ratón la fila ya está a la vista; desplazarla solo
                        // serviría para mover la lista bajo el propio puntero.
                        guard controller.selectionFromKeyboard else { return }
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }
}

struct ClipboardRow: View {
    let item: ClipItem
    let index: Int
    var showIndex = true
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showIndex && index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.quaternary))
            } else {
                Color.clear.frame(width: 18, height: 18)
            }

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .rotationEffect(.degrees(45))
            }

            preview

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.truncated
                     ? Self.timeAgo(item.date) + L(" · texto recortado", " · text trimmed")
                     : Self.timeAgo(item.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text:
            EmptyView()
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.15)))
        case .files(let urls):
            if let first = urls.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
        }
    }

    private static func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<5: return L("ahora mismo", "just now")
        case ..<60: return L("hace \(seconds) s", "\(seconds) s ago")
        case ..<3600: return L("hace \(seconds / 60) min", "\(seconds / 60) min ago")
        case ..<86_400: return L("hace \(seconds / 3600) h", "\(seconds / 3600) h ago")
        default:
            let days = seconds / 86_400
            return days == 1 ? L("hace 1 día", "1 day ago")
                             : L("hace \(days) días", "\(days) days ago")
        }
    }
}
