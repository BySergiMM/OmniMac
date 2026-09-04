import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Controles compartidos del notch

/// Botón de reproducción estilo BoringNotch: al pasar el ratón aparece un círculo
/// detrás y al pulsar se encoge. El hover llega vía HoverState porque el
/// `.onHover` de SwiftUI no funciona en este panel sin activación.
struct HoverCircleButton: View {
    let symbol: String
    let iconSize: CGFloat
    let diameter: CGFloat
    @ObservedObject var hover: HoverState
    let action: () -> Void

    @State private var frame: CGRect = .zero

    private var isHovered: Bool {
        guard let point = hover.point else { return false }
        return frame.contains(point)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .opacity(isHovered ? 1 : 0)
                    .scaleEffect(isHovered ? 1 : 0.55)
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
            }
        )
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

}

/// Se encoge al pulsar (funciona sin hover: usa isPressed del botón).
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct BatteryBadge: View {
    let state: BatteryState
    var action: () -> Void = {}

    var body: some View {
        if state.hasBattery {
            HStack(spacing: 5) {
                Text("\(state.level)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 1) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                            .frame(width: 23, height: 12)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fillColor)
                            .frame(width: max(2, 19 * CGFloat(state.level) / 100), height: 8)
                            .padding(.leading, 2)
                        if state.isPluggedIn {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.9), radius: 1)
                                .frame(width: 23)
                        }
                    }
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(.white.opacity(0.45))
                        .frame(width: 2, height: 5)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(batteryHelp + L(" · clic: Ajustes de batería", " · click: Battery settings"))
        }
    }

    private var fillColor: Color {
        if state.isPluggedIn { return .green }
        if state.level <= 20 { return .red }
        return .white.opacity(0.9)
    }

    private var batteryHelp: String {
        if state.isCharging { return L("Batería al \(state.level) % · cargando", "Battery at \(state.level) % · charging") }
        if state.isPluggedIn { return L("Batería al \(state.level) % · enchufado", "Battery at \(state.level) % · plugged in") }
        return L("Batería al \(state.level) %", "Battery at \(state.level) %")
    }
}
