import SwiftUI

/// Página «Rendimiento».
///
/// La diferencia con un monitor cualquiera está en la última sección: las gráficas
/// dicen *cuánto*, y la lista de procesos dice *quién*. Cuando el ventilador se
/// pone a soplar, lo que uno quiere es el nombre.
struct PerformancePage: View {
    @StateObject private var stats = SystemStats()
    @ObservedObject private var alerts = AlertsMonitor.shared
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

            Section {
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
                SettingToggle(title: L("Batería baja", "Low battery"),
                              subtitle: L("Por debajo del \(Int(alerts.settings.batteryPercent)) % y sin cargador.",
                                          "Below \(Int(alerts.settings.batteryPercent))% and unplugged."),
                              isOn: $alerts.settings.batteryEnabled)
            } header: {
                Text(L("Avisos", "Alerts"))
            } footer: {
                Text(L("Se mira cada minuto, y solo lo barato: CPU, memoria, disco, temperatura y batería. Cada aviso sale una vez y no se repite hasta que la cosa vuelve a estar bien. Con todos apagados, ni se mide.",
                       "Checked every minute, and only the cheap things: CPU, memory, disk, temperature and battery. Each alert fires once and won't repeat until things are back to normal. With all of them off, nothing is measured at all."))
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
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
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
