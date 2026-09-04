import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña rendimiento

struct PerformanceTab: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 10) {
            MiniChart(title: "CPU", values: stats.cpu, maxValue: 100, color: Brand.accentLight,
                      current: stats.cpu.last.map { String(format: "%.0f %%", $0) } ?? "—", compact: true)
            MiniChart(title: L("Memoria", "Memory"), values: stats.memory, maxValue: stats.memoryTotal, color: .orange,
                      current: stats.memory.last.map { String(format: "%.1f / %.0f GB", $0, stats.memoryTotal) } ?? "—", compact: true)
            MiniChart(title: L("Red", "Network"), values: stats.networkIn, secondary: stats.networkOut, color: .green,
                      current: {
                          guard let down = stats.networkIn.last, let up = stats.networkOut.last else { return "—" }
                          func rate(_ kbps: Double) -> String {
                              kbps >= 1024 ? String(format: "%.1f MB/s", kbps / 1024) : String(format: "%.0f KB/s", kbps)
                          }
                          return "↓\(rate(down)) ↑\(rate(up))"
                      }(), compact: true)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }
}
