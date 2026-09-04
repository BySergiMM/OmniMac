import AppKit
import Carbon.HIToolbox
import SwiftUI

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

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [ClipItem]) {
        allItems = items
        query = ""
        self.items = items
        selection = 0

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = FirstClickHostingView(rootView: ClipboardListView(controller: self))
        resize()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
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
        selection = 0
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch Int(event.keyCode) {
            case Int(kVK_Escape):
                if self.query.isEmpty {
                    self.hide()
                } else {
                    self.query = ""
                    self.applyFilter()
                }
                return nil
            case Int(kVK_DownArrow):
                if self.selection < self.items.count - 1 { self.selection += 1 }
                return nil
            case Int(kVK_UpArrow):
                if self.selection > 0 { self.selection -= 1 }
                return nil
            case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
                self.commit(self.selection)
                return nil
            case Int(kVK_ANSI_P) where flags.contains(.option):
                if self.items.indices.contains(self.selection) {
                    self.onPin?(self.items[self.selection])
                }
                return nil
            case Int(kVK_Delete):
                if flags.contains(.option) {
                    if self.items.indices.contains(self.selection) {
                        let item = self.items[self.selection]
                        self.onDelete?(item)
                        self.allItems.removeAll { $0.id == item.id }
                        self.applyFilter()
                    }
                } else if !self.query.isEmpty {
                    self.query.removeLast()
                    self.applyFilter()
                }
                return nil
            default:
                guard !flags.contains(.command), !flags.contains(.control),
                      let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return event }
                // Con el buscador vacío, 1–9 elige directamente.
                if self.query.isEmpty, let digit = Int(characters),
                   (1...9).contains(digit), digit <= self.items.count {
                    self.commit(digit - 1)
                    return nil
                }
                let printable = characters.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
                guard printable else { return event }
                self.query += characters
                self.applyFilter()
                return nil
            }
        }
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
                Text(L("↑↓ elegir · ↩ pegar · ⌥P anclar · ⌥⌫ borrar", "↑↓ select · ↩ paste · ⌥P pin · ⌥⌫ delete"))
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
                                             showIndex: controller.query.isEmpty,
                                             isSelected: index == controller.selection)
                                    .id(index)
                                    .onTapGesture { controller.commit(index) }
                                    .onHover { hovering in
                                        if hovering { controller.selection = index }
                                    }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: controller.selection) { _, newValue in
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
                Text(Self.timeAgo(item.date))
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
        default: return L("hace \(seconds / 86_400) días", "\(seconds / 86_400) days ago")
        }
    }
}
