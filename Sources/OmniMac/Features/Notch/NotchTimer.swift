import AppKit
import Combine
import SwiftUI

/// Temporizador del notch, con modo Pomodoro (trabajo / descanso, y descanso largo
/// cada N pomodoros). Los tiempos se cambian en Ajustes › Notch › Temporizador.
/// Mientras corre, el tiempo restante se ve junto al icono de la barra de menús.
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    enum Mode { case simple, pomodoro }
    enum Phase { case work, rest }

    // Tiempos configurables
    @Published var workMinutes: Int {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "timer.work") }
    }
    @Published var restMinutes: Int {
        didSet { UserDefaults.standard.set(restMinutes, forKey: "timer.rest") }
    }
    @Published var longRestMinutes: Int {
        didSet { UserDefaults.standard.set(longRestMinutes, forKey: "timer.longRest") }
    }
    /// Cada cuántos pomodoros toca descanso largo (0 = nunca).
    @Published var longRestEvery: Int {
        didSet { UserDefaults.standard.set(longRestEvery, forKey: "timer.longEvery") }
    }
    /// Tiempos rápidos (botones del notch), en minutos.
    @Published var presets: [Int] {
        didSet { UserDefaults.standard.set(presets, forKey: "timer.presets") }
    }

    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var running = false
    @Published private(set) var mode: Mode = .simple
    @Published private(set) var phase: Phase = .work
    @Published private(set) var completedPomodoros = 0
    @Published private(set) var isLongRest = false

    private var timer: Timer?
    private var endDate: Date?

    var isSet: Bool { total > 0 }
    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    /// "5, 10, 25, 45, 60" ↔ presets (para el campo de Ajustes).
    var presetsText: String {
        get { presets.map(String.init).joined(separator: ", ") }
        set {
            let values = newValue.split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
                .filter { (1...600).contains($0) }
            if !values.isEmpty { presets = Array(values.prefix(6)) }
        }
    }

    var remainingText: String {
        let seconds = Int(remaining.rounded(.up))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var phaseText: String {
        switch (mode, phase) {
        case (.simple, _): return L("Temporizador", "Timer")
        case (.pomodoro, .work): return L("Trabajo · pomodoro \(completedPomodoros + 1)", "Work · pomodoro \(completedPomodoros + 1)")
        case (.pomodoro, .rest): return isLongRest ? L("Descanso largo", "Long break") : L("Descanso", "Break")
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        func stored(_ key: String, _ fallback: Int) -> Int {
            let value = defaults.integer(forKey: key)
            return defaults.object(forKey: key) == nil ? fallback : value
        }
        workMinutes = stored("timer.work", 25)
        restMinutes = stored("timer.rest", 5)
        longRestMinutes = stored("timer.longRest", 15)
        longRestEvery = stored("timer.longEvery", 4)
        presets = (defaults.array(forKey: "timer.presets") as? [Int]) ?? [5, 10, 25, 45, 60]
    }

    func start(minutes: Int, mode: Mode = .simple) {
        stopTicking()
        self.mode = mode
        phase = .work
        isLongRest = false
        if mode == .pomodoro { completedPomodoros = 0 }
        begin(seconds: TimeInterval(minutes * 60))
    }

    func startPomodoro() {
        start(minutes: workMinutes, mode: .pomodoro)
    }

    func pause() {
        guard running else { return }
        stopTicking()
        running = false
    }

    func resume() {
        guard isSet, !running, remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        startTicking()
    }

    /// Vuelve al principio de la fase actual.
    func restart() {
        guard isSet else { return }
        stopTicking()
        begin(seconds: total)
    }

    func stop() {
        stopTicking()
        running = false
        total = 0
        remaining = 0
        endDate = nil
        isLongRest = false
    }

    // MARK: - Interno

    private func begin(seconds: TimeInterval) {
        total = seconds
        remaining = seconds
        endDate = Date().addingTimeInterval(seconds)
        running = true
        startTicking()
    }

    private func startTicking() {
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        stopTicking()
        running = false
        NSSound(named: "Glass")?.play()
        switch mode {
        case .simple:
            notify(title: L("Tiempo cumplido", "Time's up"), body: L("El temporizador de \(Int(total / 60)) min ha terminado.", "The \(Int(total / 60)) min timer has finished."))
            Toast.show(L("Tiempo cumplido", "Time's up"), symbol: "timer", duration: 3)
            total = 0
            remaining = 0
        case .pomodoro:
            if phase == .work {
                completedPomodoros += 1
                isLongRest = longRestEvery > 0 && completedPomodoros % longRestEvery == 0
                let rest = isLongRest ? longRestMinutes : restMinutes
                phase = .rest
                notify(title: L("Pomodoro completado", "Pomodoro complete"),
                       body: L("Llevas \(completedPomodoros). Ahora \(rest) minutos de descanso\(isLongRest ? " largo" : "").", "That makes \(completedPomodoros). Now \(rest) minutes of \(isLongRest ? "long " : "")break."))
                Toast.show(L("Pomodoro \(completedPomodoros) completado · descanso de \(rest) min", "Pomodoro \(completedPomodoros) complete · \(rest) min break"), symbol: "cup.and.saucer.fill", duration: 3)
                begin(seconds: TimeInterval(rest * 60))
            } else {
                phase = .work
                isLongRest = false
                notify(title: L("Fin del descanso", "Break over"), body: L("Empieza el pomodoro \(completedPomodoros + 1).", "Pomodoro \(completedPomodoros + 1) starts."))
                Toast.show(L("Fin del descanso · pomodoro \(completedPomodoros + 1)", "Break over · pomodoro \(completedPomodoros + 1)"), symbol: "timer", duration: 3)
                begin(seconds: TimeInterval(workMinutes * 60))
            }
        }
    }

    private func notify(title: String, body: String) {
        Notifier.post(title: title, body: body, identifier: "omnimac.timer.\(UUID().uuidString)")
    }
}

// MARK: - Pestaña del notch

struct TimerTab: View {
    @ObservedObject var timer: NotchTimer
    @ObservedObject var hover: HoverState

    var body: some View {
        if timer.isSet {
            running
        } else {
            chooser
        }
    }

    /// Sin temporizador: elige un tiempo con un clic.
    private var chooser: some View {
        VStack(spacing: 9) {
            Text(L("Elige un tiempo", "Pick a time"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                ForEach(timer.presets, id: \.self) { minutes in
                    presetButton("\(minutes) min") { timer.start(minutes: minutes) }
                }
            }
            presetButton(L("Pomodoro · \(timer.workMinutes) min de trabajo, \(timer.restMinutes) de descanso", "Pomodoro · \(timer.workMinutes) min work, \(timer.restMinutes) break"), prominent: true) {
                timer.startPomodoro()
            }
            Text(L("Los tiempos se cambian en Ajustes › Notch › Temporizador", "Times are set in Settings › Notch › Timer"))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Con temporizador: cuenta atrás grande y tres botones.
    private var running: some View {
        VStack(spacing: 6) {
            Text(timer.phaseText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(timer.remainingText)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(timer.phase == .rest ? Color.green : Brand.accentLight)
                        .frame(width: max(4, geo.size.width * timer.progress))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 40)
            HStack(spacing: 10) {
                HoverCircleButton(symbol: timer.running ? "pause.fill" : "play.fill", iconSize: 16, diameter: 34, hover: hover) {
                    if timer.running { timer.pause() } else { timer.resume() }
                }
                HoverCircleButton(symbol: "arrow.counterclockwise", iconSize: 14, diameter: 30, hover: hover) {
                    timer.restart()
                }
                HoverCircleButton(symbol: "xmark", iconSize: 14, diameter: 30, hover: hover) {
                    timer.stop()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presetButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, prominent ? 14 : 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(prominent ? Brand.accent.opacity(0.85) : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(PressScaleStyle())
    }
}
