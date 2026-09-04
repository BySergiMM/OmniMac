import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pestaña calendario

struct CalendarTab: View {
    @ObservedObject var calendar: CalendarBridge

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Group {
            if calendar.authorized == false {
                denied
            } else if calendar.events.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { calendar.refresh() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(calendar.events.prefix(4)) { event in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(nsColor: event.color))
                        .frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(event.isAllDay ? L("Todo el día", "All day") : "\(Self.time.string(from: event.start)) – \(Self.time.string(from: event.end))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    if !event.isAllDay {
                        Text(Self.relative(event))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.4))
            Text(L("Nada más por hoy", "Nothing else today"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Button(L("Abrir Calendario", "Open Calendar")) { CalendarBridge.openCalendarApp() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var denied: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.5))
            Text(L("Sin acceso al Calendario", "No access to Calendar"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Button(L("Permitir en Ajustes del Sistema", "Allow in System Settings")) { CalendarBridge.openSystemSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .underline()
        }
    }

    private static func relative(_ event: CalendarEvent) -> String {
        let now = Date()
        if event.start <= now { return "ahora" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return L("en \(max(1, minutes)) min", "in \(max(1, minutes)) min") }
        return L("en \(minutes / 60) h", "in \(minutes / 60) h")
    }
}
