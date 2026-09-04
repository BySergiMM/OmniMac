import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            // Con notch físico, plegado no se dibuja nada (el notch ya es negro); el
            // negro aparece sin animación justo al empezar a abrir. En pantallas sin
            // notch, la "isla" sí se ve siempre.
            NotchExpandedShape()
                .fill(Color.black.opacity(model.blackVisible || !model.hasNotch ? 1 : 0))
                .overlay(NotchExpandedShape().stroke(.white.opacity(model.expanded ? 0.08 : 0), lineWidth: 1))

            if !model.expanded, let peek = model.peek {
                // Vistazo rápido: una línea bajo el notch, dentro del negro.
                VStack(spacing: 0) {
                    Color.clear.frame(height: model.notchSize.height + 4)
                    HStack(spacing: 6) {
                        if let tint = peek.tint {
                            Circle()
                                .fill(Color(nsColor: tint))
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                                .frame(width: 14, height: 14)
                        }
                        Image(systemName: peek.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(peek.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !peek.subtitle.isEmpty {
                            Text("· \(peek.subtitle)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, NotchExpandedShape.flare + 12)
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


    /// Plegado = el notch exacto; con vistazo rápido crece un poco; expandido, todo.
    private var shapeSize: CGSize {
        if model.expanded {
            return CGSize(width: model.expandedSize.width + NotchExpandedShape.flare * 2,
                          height: model.expandedSize.height)
        }
        if model.peek != nil {
            return model.peekSize
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
            ForEach(NotchTab.leftTabs.filter { isTabVisible($0) }, id: \.self) { tab in
                tabButton(tab, symbol: tab.symbol, help: tab.title)
            }

            Spacer(minLength: 8)

            // A la derecha: el quinto botón a la izquierda quedaba bajo el notch físico.
            if isTabVisible(.performance) {
                tabButton(.performance, symbol: NotchTab.performance.symbol, help: NotchTab.performance.title)
            }

            if model.showCoffee, keepAwake.isEnabled {
                quickButton(symbol: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                            active: keepAwake.isActive,
                            help: keepAwake.isActive ? "Mantener despierto: activado" : "Mantener despierto") {
                    keepAwake.toggle()
                }
            }
            if model.showSettings {
                quickButton(symbol: "gearshape.fill", active: false, help: "Ajustes de OmniMac") {
                    model.onCollapseRequest?()
                    SettingsWindowController.shared.show()
                }
            }
            if model.showBattery {
                BatteryBadge(state: battery.state) {
                    // Ajustes del Sistema › Batería (modo de bajo consumo, etc.).
                    model.onCollapseRequest?()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings-extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func tabButton(_ tab: NotchTab, symbol: String, help: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.tab = tab }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.4))
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(model.tab == tab ? 0.16 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func quickButton(symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.yellow : .white.opacity(0.8))
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
                    Text("Sin pestañas activas")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Actívalas en Ajustes › Notch dinámico")
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
