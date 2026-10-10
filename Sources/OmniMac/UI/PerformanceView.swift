import SwiftUI

/// Página «Rendimiento».
///
/// La diferencia con un monitor cualquiera está en la última sección: las gráficas
/// dicen *cuánto*, y la lista de procesos dice *quién*. Cuando el ventilador se
/// pone a soplar, lo que uno quiere es el nombre.
struct PerformancePage: View {
    @StateObject private var stats = SystemStats()
    @ObservedObject private var alerts = AlertsMonitor.shared
    @StateObject private var battery = BatteryPanel()
    @State private var placement = MenuBarStats.placement

    var body: some View {
        Form {
            Section {
                SettingRow(title: L("Dónde se enseñan", "Where to show them"),
                           subtitle: placement.hint) {
                    Picker("", selection: $placement) {
                        ForEach(PerformancePlacement.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                .onChange(of: placement) { _, new in MenuBarStats.placement = new }
            } header: {
                Text(L("Gráficas", "Graphs"))
            }

            Section {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "gauge.with.dots.needle.33percent", color: .green, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Rendimiento", "Performance"))
                            .font(.title3.weight(.semibold))
                        Text(L("CPU por núcleo, GPU, memoria, disco y red del último minuto, y qué apps se lo están comiendo. Solo se mide mientras esta página o la pestaña del notch están a la vista; cerradas, no consume nada.",
                               "Per-core CPU, GPU, memory, disk and network for the last minute, plus which apps are eating them. Sampled only while this page or the notch tab is visible; closed, it costs nothing."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            // Los núcleos, uno a uno. En Apple silicon se ve de un vistazo que el
            // trabajo ligero se queda en los de eficiencia y los grandes ni se
            // enteran: eso explica por qué el Mac va fresco mejor que cualquier cifra.
            Section {
                CoreBars(values: stats.cores, layout: stats.coreLayout)
            } header: {
                Text(L("Núcleos", "Cores"))
            } footer: {
                if stats.coreLayout.efficiency > 0 {
                    Text(L("\(stats.coreLayout.efficiency) de eficiencia · \(stats.coreLayout.performance) de rendimiento",
                           "\(stats.coreLayout.efficiency) efficiency · \(stats.coreLayout.performance) performance"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                MiniChart(title: "CPU",
                          values: stats.cpu,
                          maxValue: 100,
                          color: Brand.accent,
                          current: stats.cpu.last.map { String(format: "%.0f %%", $0) } ?? "—")
            }

            // La GPU no la publican todos los Macs. Si no está, no se enseña una
            // línea plana que parezca una avería.
            if stats.gpuAvailable {
                Section {
                    MiniChart(title: "GPU",
                              values: stats.gpu,
                              maxValue: 100,
                              color: .purple,
                              current: stats.gpu.last.map { String(format: "%.0f %%", $0) } ?? "—")
                }
            }

            Section {
                MiniChart(title: L("Memoria", "Memory"),
                          values: stats.memory,
                          maxValue: stats.memoryTotal,
                          color: .orange,
                          current: stats.memory.last.map { String(format: L("%.1f de %.0f GB", "%.1f of %.0f GB"), $0, stats.memoryTotal) } ?? "—")
            } footer: {
                HStack(spacing: 6) {
                    Circle().fill(Self.pressureColor(stats.pressure)).frame(width: 7, height: 7)
                    Text(L("Presión: \(stats.pressure.title)", "Pressure: \(stats.pressure.title)"))
                    if stats.swap > 0.05 {
                        Text("·")
                        Text(L("intercambio \(String(format: "%.1f", stats.swap)) GB",
                               "swap \(String(format: "%.1f", stats.swap)) GB"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            // Los grados solo si se pueden leer. El estado térmico va siempre:
            // es lo que de verdad dice si al Mac le está costando refrigerarse.
            Section {
                if stats.temperatureAvailable, !stats.temperature.isEmpty {
                    MiniChart(title: L("Temperatura", "Temperature"),
                              values: stats.temperature,
                              maxValue: 110,
                              color: .red,
                              current: stats.temperature.last.map { String(format: "%.0f °C", $0) } ?? "—")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(Self.thermalColor(stats.thermalState)).frame(width: 7, height: 7)
                        Text(L("Estado térmico: \(Temperature.thermalTitle(stats.thermalState))",
                               "Thermal state: \(Temperature.thermalTitle(stats.thermalState))"))
                        if let max = stats.socMaxTemperature {
                            Text("·")
                            Text(L("pico \(String(format: "%.0f", max)) °C", "peak \(String(format: "%.0f", max)) °C"))
                        }
                        if let ssd = stats.ssdTemperature {
                            Text("·")
                            Text(L("SSD \(String(format: "%.0f", ssd)) °C", "SSD \(String(format: "%.0f", ssd)) °C"))
                        }
                        if let battery = stats.batteryTemperature {
                            Text("·")
                            Text(L("batería \(String(format: "%.0f", battery)) °C",
                                   "battery \(String(format: "%.0f", battery)) °C"))
                        }
                    }
                    // Se dice lo que hay: no hay temperatura por núcleo en Apple
                    // silicon, y prometerla sería inventarse un reparto.
                    if !stats.sensors.isEmpty {
                        Text(L("La media es de los \(stats.sensors.count) sensores del chip. Apple silicon no publica la temperatura de cada núcleo: los diodos van numerados y no se sabe cuál está al lado de cuál.",
                               "The average covers the chip's \(stats.sensors.count) sensors. Apple silicon doesn't publish per-core temperature: the diodes are numbered and which sits next to which isn't documented."))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            // Uno a uno, para quien quiera mirarlos.
            if !stats.sensors.isEmpty {
                Section {
                    DisclosureGroup(L("Ver los \(stats.sensors.count) sensores", "See all \(stats.sensors.count) sensors")) {
                        ForEach(stats.sensors) { sensor in
                            HStack {
                                Text(sensor.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(String(format: "%.1f °C", sensor.value))
                                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                MiniChart(title: L("Disco", "Disk"),
                          values: stats.diskRead,
                          secondary: stats.diskWrite,
                          color: .blue,
                          current: {
                              guard let read = stats.diskRead.last, let write = stats.diskWrite.last else { return "—" }
                              return "↓ \(Self.rate(read)) · ↑ \(Self.rate(write))"
                          }(),
                          legend: L("línea continua: lectura · discontinua: escritura",
                                    "solid line: read · dashed: write"))
            } footer: {
                if stats.diskTotal > 0 {
                    Text(L("\(String(format: "%.0f", stats.diskFree)) GB libres de \(String(format: "%.0f", stats.diskTotal))",
                           "\(String(format: "%.0f", stats.diskFree)) GB free of \(String(format: "%.0f", stats.diskTotal))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                MiniChart(title: L("Red", "Network"),
                          values: stats.networkIn,
                          secondary: stats.networkOut,
                          color: .green,
                          current: {
                              guard let down = stats.networkIn.last, let up = stats.networkOut.last else { return "—" }
                              return "↓ \(Self.rate(down)) · ↑ \(Self.rate(up))"
                          }(),
                          legend: L("línea continua: bajada · discontinua: subida", "solid line: download · dashed: upload"))
            }

            if let report = battery.report {
                BatterySection(report: report,
                               health: battery.health,
                               trend: battery.trend,
                               temperature: stats.batteryTemperature)
            }

            Section {
                if alerts.permission != .allowed {
                    NotificationPermissionRow(permission: alerts.permission) {
                        if alerts.permission == .notAsked {
                            alerts.askForPermission()
                        } else {
                            Notifier.openSystemSettings()
                        }
                    }
                }
                SettingToggle(title: L("La CPU lleva rato al máximo", "The CPU has been maxed out"),
                              subtitle: L("Aviso si pasa del \(Int(alerts.settings.cpuThreshold)) % durante medio minuto seguido.",
                                          "Warn if it goes above \(Int(alerts.settings.cpuThreshold))% for half a minute straight."),
                              isOn: $alerts.settings.cpuEnabled)
                SettingToggle(title: L("Memoria al límite", "Memory pressure critical"),
                              subtitle: L("Cuando el Mac empieza a comprimir memoria para que quepa todo.",
                                          "When your Mac starts compressing memory to fit everything."),
                              isOn: $alerts.settings.memoryEnabled)
                SettingToggle(title: L("Queda poco disco", "Running low on disk"),
                              subtitle: L("Por debajo de \(Int(alerts.settings.diskFreeGB)) GB libres.",
                                          "Below \(Int(alerts.settings.diskFreeGB)) GB free."),
                              isOn: $alerts.settings.diskEnabled)
                SettingToggle(title: L("El Mac se está calentando", "Your Mac is heating up"),
                              subtitle: L("Cuando macOS empieza a frenar para bajar la temperatura.",
                                          "When macOS starts throttling to cool down."),
                              isOn: $alerts.settings.thermalEnabled)
                if battery.report != nil {
                    PercentAlertRow(title: L("Batería baja: enchufa", "Low battery: plug in"),
                                    subtitle: L("Al bajar del \(Int(alerts.settings.batteryPercent)) % sin cargador.",
                                                "Below \(Int(alerts.settings.batteryPercent))% and unplugged."),
                                    percent: $alerts.settings.batteryPercent,
                                    range: 5...50,
                                    isOn: $alerts.settings.batteryEnabled)
                    PercentAlertRow(title: L("Ya puedes desenchufar", "You can unplug now"),
                                    subtitle: L("Al llegar al \(Int(alerts.settings.unplugPercent)) % enchufado. Para quedarte por debajo del límite de macOS, que empieza en el 80 %.",
                                                "When it reaches \(Int(alerts.settings.unplugPercent))% while plugged in. To stay below macOS's own limit, which starts at 80%."),
                                    percent: $alerts.settings.unplugPercent,
                                    range: 50...100,
                                    isOn: $alerts.settings.unplugEnabled)
                    SettingToggle(title: L("La batería se calienta cargando", "The battery gets hot while charging"),
                                  subtitle: L("Por encima de \(Int(AlertSettings.batteryHeatCelsius)) °C con el cargador puesto, que es cuando más se desgasta.",
                                              "Above \(Int(AlertSettings.batteryHeatCelsius)) °C while plugged in, which is when it wears the most."),
                                  isOn: $alerts.settings.batteryHeatEnabled)
                }
                SettingRow(title: L("Probar los avisos", "Test the alerts"),
                           subtitle: L("Manda uno ahora para ver dónde y cómo te llegan. Con un modo de concentración activo (No molestar, Trabajo…), macOS lo guarda en el Centro de notificaciones sin enseñarlo.",
                                       "Sends one now so you can see where and how they arrive. With a Focus on (Do Not Disturb, Work…), macOS keeps it in Notification Center without showing it.")) {
                    Button(L("Enviar un aviso de prueba", "Send a test alert")) {
                        Notifier.post(title: L("Aviso de prueba de OmniMac", "OmniMac test alert"),
                                      body: L("Así te llegarán los avisos de Rendimiento.", "This is how Performance alerts will reach you."),
                                      identifier: "alert.test.\(UUID().uuidString)")
                        alerts.refreshPermission()
                    }
                }
            } header: {
                Text(L("Avisos", "Alerts"))
            } footer: {
                Text(L("Se mira cada minuto, y solo lo barato: CPU, memoria, disco, temperatura y batería. Los grados de la batería, solo con el cargador puesto y cada dos minutos. Cada aviso sale una vez y no se repite hasta que la cosa vuelve a estar bien (el de desenchufar, en la siguiente carga). Con todos apagados, ni se mide.",
                       "Checked every minute, and only the cheap things: CPU, memory, disk, temperature and battery. Battery degrees only while plugged in, every two minutes. Each alert fires once and won't repeat until things are back to normal (the unplug one, on the next charge). With all of them off, nothing is measured at all."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Lo que de verdad se pregunta uno cuando el Mac va lento.
            Section {
                ProcessList(items: stats.topCPU, empty: L("Nada consume CPU ahora mismo.", "Nothing is using the CPU right now."),
                            value: { String(format: "%.0f %%", $0.cpu) })
            } header: {
                Text(L("Qué se está comiendo la CPU", "What's eating the CPU"))
            }

            Section {
                ProcessList(items: stats.topMemory, empty: L("Midiendo…", "Measuring…"),
                            value: { Self.bytes($0.memory) })
            } header: {
                Text(L("Qué ocupa más memoria", "What's using the most memory"))
            }
        }
        .onAppear { stats.start(); battery.start(); alerts.refreshPermission() }
        // Al volver de Ajustes del Sistema, por si se acaban de activar.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            alerts.refreshPermission()
        }
        .onDisappear { stats.stop(); battery.stop() }
    }

    private static func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }

    private static func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private static func bytes(_ value: Double) -> String {
        value >= 1_073_741_824 ? String(format: "%.1f GB", value / 1_073_741_824)
                               : String(format: "%.0f MB", value / 1_048_576)
    }

    private static func rate(_ kbps: Double) -> String {
        kbps >= 1024 ? String(format: "%.1f MB/s", kbps / 1024) : String(format: "%.0f KB/s", kbps)
    }
}

/// Salud y estado de la batería. Solo lectura: el límite de carga lo pone macOS.
struct BatterySection: View {
    let report: BatteryReport
    let health: MacHealth.Info?
    let trend: BatteryHistory.Trend?
    let temperature: Double?

    var body: some View {
        Section {
            SettingRow(title: L("Capacidad máxima", "Maximum capacity"), subtitle: capacityDetail) {
                Text(capacityText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            SettingRow(title: L("Ahora", "Now"), subtitle: nowDetail) {
                Text("\(report.percent) %")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            SettingRow(title: L("Evolución", "Over time"),
                       subtitle: trend?.summary()
                           ?? L("Se anota una lectura al día. En unas semanas verás aquí cuánto ha cambiado.",
                                "One reading a day is saved. In a few weeks you'll see here how much it has changed.")) {
                EmptyView()
            }
            SettingRow(title: L("Límite de carga", "Charge limit"),
                       subtitle: L("Lo pone macOS (26.4 o posterior): Batería › Carga › ⓘ, del 80 % al 100 %. Para parar antes, usa el aviso «Ya puedes desenchufar».",
                                   "macOS sets it (26.4 or later): Battery › Charging › ⓘ, from 80% to 100%. To stop earlier, use the “You can unplug now” alert.")) {
                Button(L("Abrir Ajustes", "Open Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } header: {
            Text(L("Batería", "Battery"))
        } footer: {
            Text(L("Todo se lee sin permisos. OmniMac no controla la carga: eso exige un ayudante con privilegios de administrador, y en los Mac recientes no hay forma documentada de hacerlo.",
                   "Everything is read without permissions. OmniMac doesn't control charging: that takes a helper with administrator privileges, and recent Macs offer no documented way to do it."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// La cifra de macOS (la misma que en Ajustes); mientras llega, la cuenta en mAh.
    private var capacityText: String {
        if let value = health?.maximumCapacity { return "\(value) %" }
        if let ratio = report.capacityRatio { return String(format: "%.0f %%", min(100, ratio)) }
        return "—"
    }

    private var capacityDetail: String {
        var parts: [String] = []
        if let condition = health?.condition {
            parts.append(L("Estado: \(MacHealth.conditionTitle(condition))", "Condition: \(MacHealth.conditionTitle(condition))"))
        }
        if let current = report.currentCapacity, let design = report.designCapacity {
            parts.append(L("\(current) de \(design) mAh de fábrica", "\(current) of \(design) mAh when new"))
        }
        if let cycles = report.cycleCount {
            if let design = report.designCycleCount {
                parts.append(L("\(cycles) ciclos de \(design) previstos", "\(cycles) of \(design) rated cycles"))
            } else {
                parts.append(L("\(cycles) ciclos", "\(cycles) cycles"))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var nowDetail: String {
        var parts = [report.statusText]
        if let watts = report.adapterWatts, report.isPluggedIn {
            parts.append(L("cargador de \(watts) W", "\(watts) W charger"))
        }
        if let temperature {
            parts.append(String(format: "%.0f °C", temperature))
        }
        return parts.joined(separator: " · ")
    }
}

/// Los avisos no se verán: o falta pedir permiso, o se denegó y hay que ir a Ajustes.
struct NotificationPermissionRow: View {
    let permission: Notifier.Permission
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
            SettingLabel(title: permission == .notAsked
                             ? L("OmniMac necesita permiso para avisarte", "OmniMac needs permission to notify you")
                             : L("Las notificaciones de OmniMac están desactivadas", "OmniMac's notifications are turned off"),
                         subtitle: permission == .notAsked
                             ? L("Sin él, estos avisos no se ven.", "Without it, these alerts won't show.")
                             : L("macOS no deja volver a preguntarlo: actívalas en Ajustes del Sistema › Notificaciones › OmniMac.",
                                 "macOS won't ask again: turn them on in System Settings › Notifications › OmniMac."))
            Spacer(minLength: 16)
            Button(permission == .notAsked ? L("Permitir", "Allow") : L("Abrir Ajustes", "Open Settings"), action: action)
        }
    }
}

/// Aviso con su porcentaje: interruptor y, al lado, el número que se puede mover.
struct PercentAlertRow: View {
    let title: String
    let subtitle: String
    @Binding var percent: Double
    let range: ClosedRange<Double>
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            HStack(spacing: 4) {
                // El número fuera del Stepper: dentro, el Form lo manda a la otra punta.
                Text("\(Int(percent)) %")
                    .monospacedDigit()
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .frame(width: 44, alignment: .trailing)
                Stepper("", value: $percent, in: range, step: 5)
                    .labelsHidden()
                    .disabled(!isOn)
                    .padding(.trailing, 6)
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

/// Una barra por núcleo. Los de eficiencia van en verde y los de rendimiento en el
/// color de la marca, en el orden en que los numera el sistema (primero los
/// pequeños).
struct CoreBars: View {
    let values: [Double]
    let layout: (efficiency: Int, performance: Int)

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if values.isEmpty {
                Text(L("Midiendo…", "Measuring…")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(.quaternary.opacity(0.5))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(index < layout.efficiency ? Color.green : Brand.accent)
                                    .frame(height: max(2, geo.size.height * CGFloat(min(1, value / 100))))
                            }
                        }
                        .frame(height: 46)
                        Text("\(Int(value))")
                            .font(.system(size: 9, design: .rounded).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        // Sin animación a propósito: animar diez barras cada dos segundos mantiene
        // el compositor despierto entre muestra y muestra, y el salto seco no se
        // nota a esta cadencia.
    }
}

/// Lista corta de procesos con su consumo. Comparte formato entre CPU y memoria.
struct ProcessList: View {
    let items: [TopProcesses.Usage]
    let empty: String
    let value: (TopProcesses.Usage) -> String

    var body: some View {
        if items.isEmpty {
            Text(empty).font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(value(item))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
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
