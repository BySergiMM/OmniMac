import AppKit
import SwiftUI

/// Tarjeta al estilo iPhone, todo sobre el mismo eje: el modelo arriba (entra con un
/// muelle), el nombre y «Conectados» debajo y, cuando llega la batería, los anillos.
struct HeadphonesCard: View {
    let info: HeadphonesInfo
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.2), .clear], center: .center, startRadius: 2, endRadius: 36))
                    .frame(width: 64, height: 64)
                Image(systemName: info.symbol)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.35)
                    .rotationEffect(.degrees(appeared ? 0 : -14))
                    .opacity(appeared ? 1 : 0)
            }
            .frame(height: 44)

            Text(info.name)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(L("Conectados", "Connected"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            if info.hasBattery {
                HStack(spacing: 14) {
                    if let level = info.left { gauge(level, symbol: info.leftSymbol, fallback: L("I", "L")) }
                    if let level = info.right { gauge(level, symbol: info.rightSymbol, fallback: L("D", "R")) }
                    if let level = info.caseLevel { gauge(level, symbol: info.caseSymbol, fallback: L("E", "C")) }
                    if let level = info.main { gauge(level, symbol: info.symbol, fallback: "") }
                }
                .padding(.top, 5)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: info)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.66).delay(0.05)) { appeared = true }
        }
    }

    private func gauge(_ level: Int, symbol: String?, fallback: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 3.2)
                Circle()
                    .trim(from: 0, to: CGFloat(max(2, min(100, level))) / 100)
                    .stroke(color(for: level), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                } else {
                    Text(fallback).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: 30)
            Text("\(level) %")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func color(for level: Int) -> Color {
        level <= 20 ? .red : (level <= 40 ? .orange : .green)
    }
}
