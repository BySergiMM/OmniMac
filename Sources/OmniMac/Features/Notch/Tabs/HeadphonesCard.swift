import AppKit
import SwiftUI

/// Tarjeta al estilo iPhone: el modelo aparece con un muelle y, cuando llega la
/// batería, cada pieza (izquierdo, derecho, estuche) entra con su anillo.
struct HeadphonesCard: View {
    let info: HeadphonesInfo
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: .center, startRadius: 6, endRadius: 64))
                    .frame(width: 128, height: 128)
                Image(systemName: info.symbol)
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.35)
                    .rotationEffect(.degrees(appeared ? 0 : -14))
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: 128)

            VStack(alignment: .leading, spacing: 5) {
                Text(info.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Conectados")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                if info.hasBattery {
                    HStack(spacing: 18) {
                        if let level = info.left { gauge(level, symbol: info.leftSymbol, fallback: "I") }
                        if let level = info.right { gauge(level, symbol: info.rightSymbol, fallback: "D") }
                        if let level = info.caseLevel { gauge(level, symbol: info.caseSymbol, fallback: "E") }
                        if let level = info.main { gauge(level, symbol: info.symbol, fallback: "") }
                    }
                    .padding(.top, 8)
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: info)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.66).delay(0.05)) { appeared = true }
        }
    }

    private func gauge(_ level: Int, symbol: String?, fallback: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(max(2, min(100, level))) / 100)
                    .stroke(color(for: level), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                } else {
                    Text(fallback).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)
            Text("\(level) %")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func color(for level: Int) -> Color {
        level <= 20 ? .red : (level <= 40 ? .orange : .green)
    }
}
