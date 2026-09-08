import AppKit
import Combine

/// Dónde se enseñan las gráficas de rendimiento.
enum PerformancePlacement: String, CaseIterable, Identifiable {
    case notch
    case menuBar
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: L("En el notch", "In the notch")
        case .menuBar: L("En la barra de menús", "In the menu bar")
        case .hidden: L("En ningún sitio", "Nowhere")
        }
    }

    var hint: String {
        switch self {
        case .notch: L("Una pestaña más al desplegar el notch.", "One more tab when the notch expands.")
        case .menuBar: L("Una gráfica pequeña junto a los demás iconos, siempre a la vista.",
                         "A small graph next to the other icons, always visible.")
        case .hidden: L("Ni se enseñan ni se mide nada.", "Neither shown nor measured.")
        }
    }
}

/// Gráfica de CPU junto a los iconos de la barra de menús.
///
/// Mide con el mismo `SystemStats` que la pestaña del notch (una muestra cada dos
/// segundos) y solo mientras está a la vista: con las gráficas en el notch o
/// apagadas, aquí no se mide nada.
@MainActor
final class MenuBarStats: ObservableObject {
    static let shared = MenuBarStats()

    static let placementKey = "performance.placement"

    /// Tamaño del dibujo en la barra: gráfica más el porcentaje.
    private static let graphSize = CGSize(width: 26, height: 14)
    private static let itemWidth: CGFloat = 60

    private var item: NSStatusItem?
    private let stats = SystemStats()
    private var cancellable: AnyCancellable?

    private init() {}

    /// Dónde están puestas ahora mismo las gráficas.
    static var placement: PerformancePlacement {
        get {
            PerformancePlacement(rawValue: UserDefaults.standard.string(forKey: placementKey) ?? "") ?? .notch
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: placementKey)
            apply(newValue)
        }
    }

    /// Lleva la elección a los dos sitios: la pestaña del notch y el icono de la barra.
    static func apply(_ placement: PerformancePlacement? = nil) {
        let placement = placement ?? Self.placement
        let notch = FeatureManager.shared.notch
        var tabs = notch.enabledTabs
        if placement == .notch { tabs.insert(.performance) } else { tabs.remove(.performance) }
        if tabs != notch.enabledTabs { notch.enabledTabs = tabs }
        shared.setVisible(placement == .menuBar)
    }

    var isVisible: Bool { item != nil }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        visible ? show() : hide()
    }

    nonisolated static let autosaveName = "com.seergiii.omnimac.stats"

    private func show() {
        // Los iconos nuevos nacen a la izquierda del todo, que es justo donde el
        // escondedor de la barra se los traga. La primera vez le damos un sitio a la
        // derecha de la flecha, con los demás iconos de OmniMac.
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(MenuBarFeature.statsPosition, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: Self.itemWidth)
        item.autosaveName = Self.autosaveName
        item.button?.target = self
        item.button?.action = #selector(openSettings)
        item.button?.imagePosition = .imageOnly
        self.item = item

        stats.start(detail: .minimal)
        // Cada muestra nueva redibuja el icono. `SystemStats` publica en el hilo
        // principal, así que no hay que saltar de hilo.
        cancellable = stats.sampled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.redraw(cpu: self?.stats.cpu ?? []) }
        redraw(cpu: stats.cpu)
    }

    private func hide() {
        cancellable = nil
        stats.stop()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    private func redraw(cpu: [Double]) {
        guard let button = item?.button else { return }
        let percent = cpu.last ?? 0
        button.image = Self.image(cpu: cpu, percent: percent)
        button.toolTip = L("CPU \(Int(percent.rounded())) %  ·  Memoria \(String(format: "%.1f", stats.memory.last ?? 0)) GB",
                           "CPU \(Int(percent.rounded()))%  ·  Memory \(String(format: "%.1f", stats.memory.last ?? 0)) GB")
    }

    /// La gráfica y el porcentaje, dibujados en una sola imagen de plantilla para que
    /// tome el color de la barra de menús (clara, oscura o con fondo).
    private static func image(cpu: [Double], percent: Double) -> NSImage {
        let size = CGSize(width: itemWidth - 8, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let graph = CGRect(x: 0, y: 1, width: graphSize.width, height: graphSize.height)

            // Suelo de la gráfica, tenue: da referencia aunque la CPU esté a cero.
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let base = NSBezierPath()
            base.move(to: CGPoint(x: graph.minX, y: graph.minY))
            base.line(to: CGPoint(x: graph.maxX, y: graph.minY))
            base.lineWidth = 1
            base.stroke()

            // Área rellena con las últimas muestras (la más nueva, a la derecha).
            let samples = Array(cpu.suffix(20))
            if samples.count > 1 {
                let step = graph.width / CGFloat(samples.count - 1)
                let path = NSBezierPath()
                path.move(to: CGPoint(x: graph.minX, y: graph.minY))
                for (index, value) in samples.enumerated() {
                    let y = graph.minY + graph.height * CGFloat(min(max(value, 0), 100) / 100)
                    path.line(to: CGPoint(x: graph.minX + step * CGFloat(index), y: y))
                }
                path.line(to: CGPoint(x: graph.maxX, y: graph.minY))
                path.close()
                NSColor.black.withAlphaComponent(0.85).setFill()
                path.fill()
            }

            // El número, a la derecha de la gráfica.
            let text = "\(Int(percent.rounded()))%"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: rect.maxX - textSize.width,
                                                y: (rect.height - textSize.height) / 2),
                                    withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L("Uso de CPU", "CPU usage")
        return image
    }
}
