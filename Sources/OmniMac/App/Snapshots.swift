import AppKit
import SwiftUI

/// Capturas reales de la interfaz para la web (`OmniMac --snapshots <carpeta>`).
/// Renderiza las vistas de verdad (el mismo `NotchView` del panel y el menú real de la
/// barra) con datos de muestra, sin permisos de grabación de pantalla, y sale.
enum Snapshots {
    static func runIfRequested(menuSource: StatusItemController) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            render(into: dir, menuSource: menuSource)
        }
        return true
    }

    // MARK: - Notch

    private static var notchSize: CGSize {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--notch-width"), i + 1 < args.count, let w = Double(args[i + 1]) {
            return CGSize(width: w, height: 32)
        }
        return CGSize(width: 185, height: 32)
    }
    private static var expandedSize: CGSize {
        CGSize(width: max(580, notchSize.width + NotchModel.sideClearance * 2), height: 196)
    }
    private static var debugNotch: Bool { CommandLine.arguments.contains("--debug-notch") }
    private static let margin: CGFloat = 36

    private static func render(into dir: URL, menuSource: StatusItemController) {
        let manager = FeatureManager.shared
        let model = NotchModel(hasNotch: true, notchSize: notchSize, expandedSize: expandedSize)
        model.expanded = true
        model.blackVisible = true
        model.showContent = true

        let media = MediaBridge()
        media.useSample(NowPlayingInfo(playerName: "Spotify", bundleID: "com.spotify.client",
                                       title: L("Todo lo que le falta a tu Mac", "Everything your Mac is missing"), artist: "OmniMac",
                                       isPlaying: true, artworkURL: nil, position: 72, duration: 188),
                        artwork: sampleArtwork())
        let battery = BatteryMonitor()
        battery.useSample(BatteryState(hasBattery: true, level: 84, isCharging: false, isPluggedIn: false))
        let calendar = CalendarBridge()
        calendar.useSample(sampleEvents())
        let sound = manager.sound
        sound.refresh()
        sound.useSample(outputVolume: 0.62)
        sound.mixer.useSample(sampleApps())
        let stats = SystemStats()
        stats.useSample(cpu: wave(60, base: 14, amp: 12, period: 17),
                        memory: wave(60, base: 11.2, amp: 0.5, period: 23),
                        networkIn: wave(60, base: 180, amp: 160, period: 9),
                        networkOut: wave(60, base: 40, amp: 30, period: 13))
        model.shelf = sampleFiles(in: dir)
        NotchTimer.shared.start(minutes: 25)

        let view = NotchView(model: model, media: media, battery: battery,
                             keepAwake: manager.keepAwake, calendar: calendar, sound: sound, stats: stats)
        let size = CGSize(width: expandedSize.width + margin * 2, height: expandedSize.height + margin)
        let notchWidth = notchSize.width
        let hosting = NSHostingView(rootView: view.overlay(alignment: .top) {
            // Con --debug-notch: dónde queda el notch físico, para comprobar que nada se esconde debajo.
            if debugNotch {
                Rectangle().fill(Color.red.opacity(0.45)).frame(width: notchWidth, height: notchSize.height)
            }
        })
        let window = offscreenWindow(size: size, content: hosting)

        let tabs: [NotchTab] = [.media, .tray, .calendar, .sound, .timer, .performance]
        var pending = tabs
        func next() {
            guard let tab = pending.first else {
                NotchTimer.shared.stop()
                // Tarjeta «AirPods conectados» (con su animación ya asentada).
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { model.deviceCard = HeadphonesInfo.sample }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    save(hosting, to: dir.appendingPathComponent("notch-headphones.png"))
                    window.orderOut(nil)
                    renderMenu(into: dir, source: menuSource) { NSApp.terminate(nil) }
                }
                return
            }
            pending.removeFirst()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.tab = tab }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                save(hosting, to: dir.appendingPathComponent("notch-\(tab.rawValue).png"))
                next()
            }
        }
        next()
    }

    // MARK: - Menú de la barra

    private static func renderMenu(into dir: URL, source: StatusItemController, completion: @escaping () -> Void) {
        let menu = NSMenu()
        source.menuNeedsUpdate(menu)
        let lines: [MenuLine] = menu.items.map { item in
            if item.isSeparatorItem { return .separator }
            if item.isSectionHeader { return .header(item.title) }
            let keys = item.keyEquivalent.isEmpty ? "" : "⌘" + item.keyEquivalent.uppercased()
            // Estado de muestra: la salida no está silenciada en la captura.
            let checked = item.state == .on && item.title != L("Silenciar la salida", "Mute the output")
            return .item(item.title, submenu: item.submenu != nil, checked: checked,
                         enabled: item.isEnabled, keys: keys)
        }
        let view = MenuSnapshotView(lines: lines, highlighted: L("Activar 1 hora", "Keep awake for 1 hour"))
        let hosting = NSHostingView(rootView: view)
        let height = lines.reduce(CGFloat(12)) { $0 + $1.height }
        let window = offscreenWindow(size: CGSize(width: 320 + 60, height: height + 60), content: hosting)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            save(hosting, to: dir.appendingPathComponent("menu.png"))
            window.orderOut(nil)
            completion()
        }
    }

    // MARK: - Ayudas

    private static func offscreenWindow(size: CGSize, content: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        content.frame = CGRect(origin: .zero, size: size)
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return window
    }

    private static func save(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("📸 \(url.lastPathComponent) \(rep.pixelsWide)×\(rep.pixelsHigh)")
        }
    }

    private static func wave(_ n: Int, base: Double, amp: Double, period: Double) -> [Double] {
        (0..<n).map { i in
            let t = Double(i)
            return max(0, base + amp * sin(t / period * 2 * .pi) + amp * 0.35 * sin(t / 3.1))
        }
    }

    private static func sampleArtwork() -> NSImage {
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(red: 0.97, green: 0.65, blue: 0.75, alpha: 1),
                            NSColor(red: 0.49, green: 0.42, blue: 0.94, alpha: 1),
                            NSColor(red: 0.23, green: 0.82, blue: 1.0, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -45)
        if let icon = NSApp.applicationIconImage {
            icon.draw(in: NSRect(x: 60, y: 60, width: 180, height: 180))
        }
        image.unlockFocus()
        return image
    }

    private static func sampleEvents() -> [CalendarEvent] {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.dateInterval(of: .hour, for: now)?.end ?? now   // la próxima hora en punto
        func at(_ h: Double, minutes: Double) -> (Date, Date) {
            let start = hour.addingTimeInterval(h * 3600)
            return (start, start.addingTimeInterval(minutes * 60))
        }
        let (s1, e1) = at(0, minutes: 45), (s2, e2) = at(2, minutes: 60), (s3, e3) = at(5, minutes: 60)
        return [
            CalendarEvent(id: "1", title: L("Reunión de equipo", "Team meeting"), start: s1, end: e1, isAllDay: false, color: .systemBlue),
            CalendarEvent(id: "2", title: L("Comida con Marta", "Lunch with Marta"), start: s2, end: e2, isAllDay: false, color: .systemOrange),
            CalendarEvent(id: "3", title: L("Gimnasio", "Gym"), start: s3, end: e3, isAllDay: false, color: .systemGreen),
        ]
    }

    private static func sampleApps() -> [AudioApp] {
        func app(_ name: String, _ path: String, _ volume: Float, playing: Bool = true) -> AudioApp {
            let icon = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
            return AudioApp(key: path, pid: 0, name: name, icon: icon, processObjects: [], isPlaying: playing, volume: volume)
        }
        return [app("Spotify", "/Applications/Spotify.app", 0.4),
                app("Safari", "/Applications/Safari.app", 1.0),
                app("FaceTime", "/System/Applications/FaceTime.app", 0.75, playing: false)]
    }

    private static func sampleFiles(in dir: URL) -> [URL] {
        let folder = dir.appendingPathComponent("bandeja", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ["Informe trimestral.pdf", "Portada.png", "Notas de la reunión.txt"].map { name in
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) { try? Data().write(to: url) }
            return url
        }
    }
}

// MARK: - Réplica fiel del menú (mismos elementos que el menú real)

enum MenuLine {
    case separator
    case header(String)
    case item(String, submenu: Bool, checked: Bool, enabled: Bool, keys: String)

    var height: CGFloat {
        switch self {
        case .separator: 11
        case .header: 20
        case .item: 22
        }
    }
}

struct MenuSnapshotView: View {
    let lines: [MenuLine]
    var highlighted: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.95, green: 0.95, blue: 0.96))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .padding(30)
    }

    @ViewBuilder
    private func row(_ line: MenuLine) -> some View {
        switch line {
        case .separator:
            Rectangle().fill(.black.opacity(0.1)).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 5)
        case .header(let title):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .frame(height: 20, alignment: .leading)
        case .item(let title, let submenu, let checked, let enabled, let keys):
            let hot = title == highlighted
            HStack(spacing: 0) {
                Text(checked ? "✓" : "")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if submenu {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).opacity(0.55)
                } else if !keys.isEmpty {
                    Text(keys).font(.system(size: 12)).opacity(0.55)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .foregroundStyle(hot ? Color.white : (enabled ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hot ? Color(nsColor: .controlAccentColor) : .clear)
                    .padding(.horizontal, 5)
            )
        }
    }
}
