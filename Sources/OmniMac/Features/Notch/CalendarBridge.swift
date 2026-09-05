import AppKit
import Combine
import EventKit

/// Un evento de hoy, tal como lo enseña la pestaña Calendario del notch.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
}

/// Eventos de hoy para la pestaña Calendario del notch. Solo consulta al abrir la
/// pestaña; pide permiso la primera vez.
final class CalendarBridge: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    /// nil = aún no decidido; false = denegado.
    @Published private(set) var authorized: Bool?

    private let store = EKEventStore()

    private var sampleMode = false

    /// Solo para las capturas de la web.
    func useSample(_ sample: [CalendarEvent]) {
        sampleMode = true
        authorized = true
        events = sample
    }

    func refresh() {
        guard !sampleMode else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            authorized = true
            load()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.authorized = granted
                    if granted { self?.load() }
                }
            }
        default:
            authorized = false
        }
    }

    private func load() {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { $0.isAllDay || $0.endDate > now }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return !a.isAllDay } // los de hora concreta primero
                return a.startDate < b.startDate
            }
        events = upcoming.prefix(6).map {
            CalendarEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                          title: $0.title ?? L("(Sin título)", "(Untitled)"),
                          start: $0.startDate,
                          end: $0.endDate,
                          isAllDay: $0.isAllDay,
                          color: $0.calendar.color ?? .systemBlue)
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}
