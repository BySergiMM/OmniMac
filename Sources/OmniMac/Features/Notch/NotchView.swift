import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Símbolos SF que usa el notch (pestañas y zonas).
enum NotchSymbols {
    /// El símbolo "airdrop" existe desde SF Symbols 6; si no está, usamos uno parecido.
    static let airdrop: String =
        NSImage(systemSymbolName: "airdrop", accessibilityDescription: nil) != nil
        ? "airdrop"
        : "dot.radiowaves.left.and.right"
}

/// Forma del notch expandido, como el notch físico: arriba las esquinas se abren
/// HACIA FUERA (el negro se ensancha al llegar al techo con una curva cóncava) y
/// abajo van redondeadas. El cuerpo ocupa `rect` menos `flare` a cada lado; las
/// "alas" de arriba usan ese margen.
struct NotchExpandedShape: Shape {
    static let flare: CGFloat = 14
    var bottomCorner: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let W = rect.width, H = rect.height
        let r = min(Self.flare, W / 4, H / 2)
        let rb = min(bottomCorner, (W - 2 * r) / 2, max(0, H - r))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: W, y: 0))
        p.addQuadCurve(to: CGPoint(x: W - r, y: r), control: CGPoint(x: W - r, y: 0))      // ala sup. der
        p.addLine(to: CGPoint(x: W - r, y: H - rb))
        p.addQuadCurve(to: CGPoint(x: W - r - rb, y: H), control: CGPoint(x: W - r, y: H))  // inf. der
        p.addLine(to: CGPoint(x: r + rb, y: H))
        p.addQuadCurve(to: CGPoint(x: r, y: H - rb), control: CGPoint(x: r, y: H))          // inf. izq
        p.addLine(to: CGPoint(x: r, y: r))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: r, y: 0))                // ala sup. izq
        p.closeSubpath()
        return p
    }
}

/// Marcos de los iconos de la izquierda, que la vista publica hacia arriba para que
/// el arrastre se pueda llevar en AppKit (ver `NotchWindowController`): los eventos
/// de la franja bajo la barra de menús llegan por un tap y SwiftUI no puede seguir
/// un arrastre con ellos.
struct TabFramesKey: PreferenceKey {
    static var defaultValue: [NotchTab: CGRect] = [:]
    static func reduce(value: inout [NotchTab: CGRect], nextValue: () -> [NotchTab: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaBridge
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var keepAwake: KeepAwakeFeature
    @ObservedObject var calendar: CalendarBridge
    @ObservedObject var sound: SoundFeature
    @ObservedObject var stats: SystemStats
    /// Marco de la zona AirDrop en coordenadas del notch (para decidir dónde cae la suelta).
    @State private var airDropFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            // La misma forma en ambos estados: así el paso plegado→expandido es una
            // sola animación continua del marco, que crece desde el centro del notch.
            // Con notch físico, plegado no se dibuja nada (el notch ya es negro); el
            // negro aparece sin animación justo al empezar a abrir. En pantallas sin
            // notch, la "isla" sí se ve siempre.
            NotchExpandedShape()
                .fill(Color.black.opacity(model.blackVisible || !model.hasNotch ? 1 : 0))
                .overlay(NotchExpandedShape().stroke(.white.opacity(model.expanded ? 0.08 : 0), lineWidth: 1))

            if !model.expanded, model.peek == nil, model.activityVisible {
                // Música sonando: carátula a la izquierda del notch y ondas a la derecha.
                HStack(spacing: 0) {
                    // Centradas en la parte visible del ala: la curva de arriba se
                    // come `flare` puntos por fuera.
                    activityArtwork
                        .frame(width: PeekLayout.activityWing - NotchExpandedShape.flare)
                        .padding(.leading, NotchExpandedShape.flare)
                    Color.clear.frame(width: model.notchSize.width)
                    AudioBars()
                        .frame(width: 20, height: 15)
                        .frame(width: PeekLayout.activityWing - NotchExpandedShape.flare)
                        .padding(.trailing, NotchExpandedShape.flare)
                }
                .frame(height: model.notchSize.height)
                .transition(.opacity)
            }

            if !model.expanded, let peek = model.peek {
                Group {
                    if model.peekPlacement == .sides && model.peekLayout.wing > 0 {
                        // A los lados: icono en el ala izquierda y texto (o barra) en
                        // la derecha, a la altura del notch; el hueco del medio es el
                        // notch físico, donde no se ve nada.
                        HStack(spacing: 0) {
                            peekLeading(peek)
                                .padding(.leading, NotchExpandedShape.flare + 10)
                                .frame(width: model.peekLayout.wing, alignment: .leading)
                            Color.clear.frame(width: model.notchSize.width)
                            peekContent(peek, showPercent: false)
                                .padding(.leading, 8)
                                .padding(.trailing, NotchExpandedShape.flare + 10)
                                .frame(width: model.peekLayout.wing, alignment: .leading)
                        }
                        .frame(height: model.notchSize.height)
                    } else {
                        // Debajo: una línea bajo el notch, dentro del negro.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: model.notchSize.height + 4)
                            HStack(spacing: 6) {
                                peekLeading(peek)
                                peekContent(peek, showPercent: true)
                            }
                            .padding(.horizontal, NotchExpandedShape.flare + 12)
                        }
                    }
                }
                .transition(.opacity)
            }

            if model.showContent {
                VStack(spacing: 0) {
                    // La barra de control sube a la altura de la barra de menús; sus
                    // clics los reenvía el forwardTap (si no, el sistema se los traga).
                    Color.clear.frame(height: max(2, model.notchSize.height - 28))
                    if let card = model.deviceCard {
                        HeadphonesCard(info: card)
                            .padding(.top, 28)   // debajo del notch físico
                            .transition(.opacity)
                    } else {
                        controlBar
                        content
                    }
                }
                .padding(.horizontal, NotchExpandedShape.flare) // el contenido va en el cuerpo, no en las alas
                // El contenido emerge escalando desde el centro-arriba (el notch).
                .transition(.scale(scale: 0.86, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(width: shapeSize.width, height: shapeSize.height)
        .clipShape(NotchExpandedShape()) // nada asoma fuera del negro durante la animación
        // Un solo plano antes de la sombra: así la sombra se calcula del conjunto y no
        // de cada subvista (con contenido semitransparente animándose, se «rompía»).
        .compositingGroup()
        // Sombra exterior en dos capas: una pegada al borde (marca hasta dónde llega
        // el notch) y otra amplia y suave (le da peso). Solo expandido (o en el vistazo).
        .shadow(color: .black.opacity(model.expanded ? 0.55 : (model.peek != nil ? 0.4 : 0)),
                radius: model.expanded || model.peek != nil ? 3 : 0,
                y: model.expanded || model.peek != nil ? 1 : 0)
        .shadow(color: .black.opacity(model.expanded ? 0.38 : 0),
                radius: model.expanded ? 16 : 0,
                y: model.expanded ? 8 : 0)
        .onHover { hovering in
            model.onHoverChange?(hovering)
        }
        .onTapGesture {
            if !model.expanded { model.onExpandRequest?() }
        }
        // Un único destino de arrastre para todo el notch: SwiftUI entrega la suelta al
        // destino exterior aunque haya otros dentro, así que aquí decidimos por
        // posición si el archivo va a la bandeja o a AirDrop.
        .coordinateSpace(name: "notch")
        .onDrop(of: [.fileURL], delegate: NotchDropDelegate(model: model, airDropFrame: { airDropFrame }))
        .onPreferenceChange(AirDropFrameKey.self) { airDropFrame = $0 }
    }


    /// Carátula de lo que suena (o una nota si aún no ha llegado).
    @ViewBuilder
    private var activityArtwork: some View {
        if let image = media.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    /// Lo de la izquierda del vistazo: el color (si lo hay) y el icono.
    @ViewBuilder
    private func peekLeading(_ peek: PeekInfo) -> some View {
        HStack(spacing: 6) {
            if let tint = peek.tint {
                Circle()
                    .fill(Color(nsColor: tint))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .frame(width: 14, height: 14)
            }
            Image(systemName: peek.symbol)
                .font(.system(size: peek.level == nil ? 10 : 12, weight: .bold))
                .foregroundStyle(.white.opacity(peek.level == nil ? 0.7 : 0.9))
                .frame(minWidth: 16)
        }
    }

    /// El texto del aviso o, en el HUD, la barra del nivel.
    @ViewBuilder
    private func peekContent(_ peek: PeekInfo, showPercent: Bool) -> some View {
        if let level = peek.level {
            HStack(spacing: 8) {
                LevelBar(value: level)
                    .frame(width: PeekLayout.levelBarWidth, height: 5)
                if showPercent {
                    Text("\(Int((level * 100).rounded())) %")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(peek.title)
            .accessibilityValue("\(Int((level * 100).rounded())) %")
        } else {
            HStack(spacing: 6) {
                Text(peek.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !peek.subtitle.isEmpty {
                    Text("· \(peek.subtitle)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }

    /// Plegado = el notch exacto; con vistazo rápido crece un poco; expandido, todo.
    private var shapeSize: CGSize {
        if model.expanded {
            let size = model.deviceCard != nil ? model.cardSize : model.expandedSize
            return CGSize(width: size.width + NotchExpandedShape.flare * 2,
                          height: size.height)
        }
        if model.peek != nil {
            return model.peekSize
        }
        if model.activityVisible {
            return model.activitySize
        }
        return model.notchSize
    }

    /// Una pestaña se ve si está activada en Ajustes y, en el caso de Sonido, si el
    /// módulo Sonido también lo está.
    private func isTabVisible(_ tab: NotchTab) -> Bool {
        guard model.enabledTabs.contains(tab) else { return false }
        if tab == .sound { return sound.isEnabled }
        return true
    }

    // MARK: - Barra de control (debajo de la barra de menús → clicable)

    private var controlBar: some View {
        HStack(spacing: 6) {
            // Solo las pestañas activadas en Ajustes (y Sonido solo si su módulo está activo).
            ForEach(model.tabOrder.filter { isTabVisible($0) }, id: \.self) { tab in
                tabButton(tab, symbol: tab.symbol, help: tab.title)
            }

            Spacer(minLength: 8)

            // A la derecha: el quinto botón a la izquierda quedaba bajo el notch físico.
            if isTabVisible(.performance) {
                tabButton(.performance, symbol: NotchTab.performance.symbol, help: NotchTab.performance.title)
            }

            if model.showCoffee, keepAwake.isEnabled {
                // Si la última sesión se paró sola, el icono lo dice: era la única
                // pista que faltaba para no tener que adivinarlo.
                let stoppedItself = keepAwake.lastEnding?.worthTelling == true && !keepAwake.isActive
                quickButton(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                            active: keepAwake.isActive,
                            warning: stoppedItself,
                            help: keepAwake.isActive
                                ? L("Mantener despierto: activado", "Keep awake: on")
                                : (keepAwake.lastEnding?.worthTelling == true
                                   ? keepAwake.lastEnding!.explanation
                                   : L("Mantener despierto", "Keep awake"))) {
                    keepAwake.toggle()
                }
            }
            if model.showSettings {
                quickButton(symbol: "gearshape.fill", active: false, help: L("Ajustes de OmniMac", "OmniMac settings")) {
                    model.onCollapseRequest?()
                    SettingsWindowController.shared.show()
                }
            }
            if model.showBattery {
                BatteryBadge(state: battery.state) {
                    // Ajustes del Sistema › Batería (modo de bajo consumo, etc.). Ojo al
                    // punto de «.extension»: con guion ese panel no existe, y Ajustes del
                    // Sistema abre General —o se queda donde estaba— sin dar ningún error.
                    model.onCollapseRequest?()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        // Dónde ha quedado cada icono, para que el controlador pueda arrastrarlos.
        .onPreferenceChange(TabFramesKey.self) { frames in
            model.tabFrames = frames
        }
    }

    /// Ancho de un icono más su separación: lo que hay que recorrer para adelantar a
    /// otro mientras se arrastra.
    private static let tabStep: CGFloat = 38

    private func tabButton(_ tab: NotchTab, symbol: String, help: String) -> some View {
        let isDragging = model.draggingTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { model.tab = tab }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.4))
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(isDragging ? 0.28 : (model.tab == tab ? 0.16 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("\(help) · ⌘ y arrastra para cambiarlo de sitio",
                "\(help) · ⌘-drag to move it"))
        // El arrastre lo lleva el controlador (ver `NotchWindowController`), porque
        // los eventos de esta franja llegan por un tap y SwiftUI no puede seguir un
        // arrastre con ellos. Aquí solo se publica dónde está cada icono y se pinta
        // el que se esté moviendo.
        .offset(x: isDragging ? model.tabDragOffset : 0)
        .scaleEffect(isDragging ? 1.12 : 1)
        .zIndex(isDragging ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: TabFramesKey.self, value: [tab: geometry.frame(in: .global)])
            }
        )
    }

    private func quickButton(symbol: String, active: Bool, warning: Bool = false,
                             help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.yellow : (warning ? Color.orange : .white.opacity(0.8)))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(active ? 0.18 : 0.07))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Contenido

    private var content: some View {
        Group {
            if !isTabVisible(model.tab) {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(L("Sin pestañas activas", "No tabs enabled"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(L("Actívalas en Ajustes › Notch dinámico", "Enable them in Settings › Dynamic notch"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.tab {
                case .media: MediaTab(media: media, hover: model.hover)
                case .tray: TrayTab(model: model)
                case .calendar: CalendarTab(calendar: calendar)
                case .sound: SoundTab(sound: sound, mixer: sound.mixer)
                case .timer: TimerTab(timer: NotchTimer.shared, hover: model.hover)
                case .performance: PerformanceTab(stats: stats)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

/// Barra del HUD de volumen y brillo: una cápsula que se llena de blanco.
private struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        // El salto entre pulsaciones se anima, como en la barra de macOS.
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

/// Ondas de «música sonando»: cuatro barras que suben y bajan.
///
/// Con Core Animation y no con SwiftUI: una animación de SwiftUI (o un efecto de
/// símbolo) repinta la app en cada fotograma, y con la música puesta eso eran un
/// 15 % de CPU todo el rato. Una `CABasicAnimation` la mueve el servidor de ventanas
/// por su cuenta y la app no se despierta.
private struct AudioBars: NSViewRepresentable {
    func makeNSView(context: Context) -> AudioBarsView { AudioBarsView() }
    func updateNSView(_ nsView: AudioBarsView, context: Context) {}
}

private final class AudioBarsView: NSView {
    private var bars: [CALayer] = []
    /// Cada barra con su ritmo, para que no suban todas a la vez.
    private let durations: [CFTimeInterval] = [0.45, 0.62, 0.38, 0.54]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in durations {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    override func layout() {
        super.layout()
        let gap: CGFloat = 2
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + gap) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
        startAnimating()
    }

    private func startAnimating() {
        for (index, bar) in bars.enumerated() where bar.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.3
            pulse.toValue = 1
            pulse.duration = durations[index]
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.timeOffset = Double(index) * 0.17
            bar.add(pulse, forKey: "pulse")
        }
    }
}
