import SwiftUI

/// Página «Rendimiento»: tres gráficos básicos del último minuto.
struct PerformancePage: View {
    @StateObject private var stats = SystemStats()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "gauge.with.dots.needle.33percent", color: .green, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rendimiento")
                            .font(.title3.weight(.semibold))
                        Text("CPU, memoria y red del último minuto. Solo se mide mientras esta página o la pestaña del notch están a la vista; cerradas, no consume nada.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                MiniChart(title: "CPU",
                          values: stats.cpu,
                          maxValue: 100,
                          color: Brand.accent,
                          current: stats.cpu.last.map { String(format: "%.0f %%", $0) } ?? "—")
            }
            Section {
                MiniChart(title: "Memoria",
                          values: stats.memory,
                          maxValue: stats.memoryTotal,
                          color: .orange,
                          current: stats.memory.last.map { String(format: "%.1f de %.0f GB", $0, stats.memoryTotal) } ?? "—")
            }
            Section {
                MiniChart(title: "Red",
                          values: stats.networkIn,
                          secondary: stats.networkOut,
                          color: .green,
                          current: {
                              guard let down = stats.networkIn.last, let up = stats.networkOut.last else { return "—" }
                              return "↓ \(Self.rate(down)) · ↑ \(Self.rate(up))"
                          }(),
                          legend: "línea continua: bajada · discontinua: subida")
            }
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private static func rate(_ kbps: Double) -> String {
        kbps >= 1024 ? String(format: "%.1f MB/s", kbps / 1024) : String(format: "%.0f KB/s", kbps)
    }
}

/// Gráfico de línea con área, escala fija u automática; las muestras entran por la derecha.
struct MiniChart: View {
    let title: String
    let values: [Double]
    var secondary: [Double] = []
    var maxValue: Double? = nil
    let color: Color
    let current: String
    var legend: String? = nil
    /// Versión pequeña para el notch (fondo negro, texto blanco).
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(compact ? .system(size: 11, weight: .semibold) : .headline)
                    .foregroundStyle(compact ? Color.white.opacity(0.75) : Color.primary)
                if let legend, !compact {
                    Text(legend)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(current)
                    .font(.system(size: compact ? 10.5 : 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(compact ? Color.white.opacity(0.9) : Color.secondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                let top = maxValue ?? max(1, (values + secondary).max() ?? 1) * 1.15
                ZStack(alignment: .bottomLeading) {
                    grid(in: geo.size)
                    area(values, in: geo.size, top: top)
                        .fill(color.opacity(0.18))
                    line(values, in: geo.size, top: top)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    if !secondary.isEmpty {
                        line(secondary, in: geo.size, top: top)
                            .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
            }
            .frame(height: compact ? 64 : 92)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(compact ? AnyShapeStyle(Color.white.opacity(0.07)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func grid(in size: CGSize) -> some View {
        Path { path in
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke((compact ? Color.white : Color.primary).opacity(0.08), lineWidth: 1)
    }

    private func points(_ data: [Double], in size: CGSize, top: Double) -> [CGPoint] {
        let n = SystemStats.capacity
        let offset = n - data.count
        return data.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(offset + index) / CGFloat(n - 1),
                    y: size.height - size.height * CGFloat(min(1, max(0, value / top))))
        }
    }

    private func line(_ data: [Double], in size: CGSize, top: Double) -> Path {
        var path = Path()
        let pts = points(data, in: size, top: top)
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func area(_ data: [Double], in size: CGSize, top: Double) -> Path {
        var path = Path()
        let pts = points(data, in: size, top: top)
        guard let first = pts.first, let last = pts.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        for point in pts { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
