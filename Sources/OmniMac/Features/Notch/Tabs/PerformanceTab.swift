import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña rendimiento

struct PerformanceTab: View {
    @ObservedObject var stats: SystemStats

    /// Con cuatro gráficas en el ancho del notch, «135 KB/s» no cabe y se corta.
    /// Aquí se abrevia: la unidad se sobreentiende y lo que importa es el número.
    private static func rate(_ kbps: Double) -> String {
        kbps >= 1024 ? String(format: "%.1fM", kbps / 1024) : String(format: "%.0fK", kbps)
    }

    var body: some View {
        HStack(spacing: 10) {
            MiniChart(title: "CPU", values: stats.cpu, maxValue: 100, color: Brand.accentLight,
                      current: stats.cpu.last.map { String(format: "%.0f %%", $0) } ?? "—", compact: true)
            // La GPU solo si este Mac la publica: en el notch no sobra sitio para
            // una gráfica que sería una línea plana.
            if stats.gpuAvailable {
                MiniChart(title: "GPU", values: stats.gpu, maxValue: 100, color: .purple,
                          current: stats.gpu.last.map { String(format: "%.0f %%", $0) } ?? "—", compact: true)
            }
            MiniChart(title: L("Memoria", "Memory"), values: stats.memory, maxValue: stats.memoryTotal, color: .orange,
                      current: stats.memory.last.map { String(format: "%.1f / %.0f GB", $0, stats.memoryTotal) } ?? "—", compact: true)
            MiniChart(title: L("Red", "Network"), values: stats.networkIn, secondary: stats.networkOut, color: .green,
                      current: {
                          guard let down = stats.networkIn.last, let up = stats.networkOut.last else { return "—" }
                          return "↓\(Self.rate(down)) ↑\(Self.rate(up))"
                      }(), compact: true)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }
}
