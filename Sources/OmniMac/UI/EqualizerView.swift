import SwiftUI

/// Los diez deslizadores del ecualizador, con sus ajustes preparados.
///
/// No sabe de dónde salen las ganancias: se le pasan y se le dice qué hacer al
/// cambiarlas. Así vale igual para el ecualizador general y para el de cada app.
struct EqualizerView: View {
    let gains: [Double]
    let setBand: (Int, Double) -> Void
    let setAll: ([Double]) -> Void
    var compact = false

    private var isActive: Bool { gains.contains { abs($0) > 0.01 } }

    private var selectedPreset: String {
        EqualizerPreset.matching(gains)?.id ?? "custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: Binding(
                    get: { selectedPreset },
                    set: { id in
                        if let preset = EqualizerPreset.all.first(where: { $0.id == id }) {
                            setAll(preset.gains)
                        }
                    })) {
                    ForEach(EqualizerPreset.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    if selectedPreset == "custom" {
                        Divider()
                        Text(L("A tu gusto", "Custom")).tag("custom")
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                Button(L("Poner a cero", "Reset")) { setAll(EqualizerPreset.flat.gains) }
                    .disabled(!isActive)
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<EqualizerBands.count, id: \.self) { band in
                    BandSlider(band: band,
                               gain: band < gains.count ? gains[band] : 0,
                               trackHeight: compact ? 84 : 120,
                               onChange: { setBand(band, $0) })
                }
            }
            .frame(height: compact ? 136 : 172)
        }
        .padding(.vertical, 4)
    }
}

/// Un deslizador vertical con su frecuencia debajo y los decibelios encima.
///
/// Está dibujado a mano en vez de girar un `Slider` 90°: girado, SwiftUI no respeta
/// la longitud que se le pide y el recorrido sale a la mitad. Así además se puede
/// marcar el centro (0 dB) y volver a él con doble clic.
private struct BandSlider: View {
    let band: Int
    let gain: Double
    let trackHeight: CGFloat
    let onChange: (Double) -> Void

    private static let knob: CGFloat = 15

    /// 0 arriba (+12 dB) … 1 abajo (−12 dB).
    private var fraction: CGFloat {
        CGFloat((EqualizerBands.limitDB - gain) / (EqualizerBands.limitDB * 2))
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(gain == 0 ? "0" : String(format: "%+.0f", gain))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(gain == 0 ? .tertiary : .secondary)

            GeometryReader { geometry in
                let usable = geometry.size.height - Self.knob
                let center = geometry.size.height / 2
                let position = Self.knob / 2 + usable * fraction

                ZStack(alignment: .top) {
                    // Carril
                    Capsule()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Marca del centro (0 dB)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 12, height: 1)
                        .offset(y: center - 0.5)

                    // Lo que se ha movido desde el centro
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: abs(position - center))
                        .offset(y: min(position, center))

                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                        .frame(width: Self.knob, height: Self.knob)
                        .offset(y: position - Self.knob / 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let y = min(max(value.location.y - Self.knob / 2, 0), usable)
                            let ratio = usable > 0 ? Double(y / usable) : 0.5
                            let db = EqualizerBands.limitDB - ratio * EqualizerBands.limitDB * 2
                            // Redondeo a medio decibelio y enganche en el cero.
                            let rounded = (db * 2).rounded() / 2
                            onChange(abs(rounded) < 0.8 ? 0 : rounded)
                        }
                )
                .onTapGesture(count: 2) { onChange(0) }
            }
            .frame(width: 26, height: trackHeight)

            Text(EqualizerBands.label(band))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help(L("\(EqualizerBands.label(band)) Hz · doble clic para volver a cero",
                "\(EqualizerBands.label(band)) Hz · double-click to reset"))
    }
}
